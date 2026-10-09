// Curated app screenshots for the marketing site.
// Serve web/dist on :8765 first (python3 -m http.server 8765 -d web/dist), then:
//   node capture_screens.mjs OUT_DIR
// Needs puppeteer-core and @sparticuz/chromium (npm i puppeteer-core @sparticuz/chromium).
import chromium from '@sparticuz/chromium';
import puppeteer from 'puppeteer-core';
import fs from 'node:fs';
const OUT = process.argv[2];
fs.mkdirSync(OUT, { recursive: true });
const b = await puppeteer.launch({ executablePath: await chromium.executablePath(), args: chromium.args, headless: true });
const errors = [];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function page(w = 390, h = 844, dpr = 2) {
  const p = await b.newPage();
  await p.setViewport({ width: w, height: h, deviceScaleFactor: dpr });
  p.on('pageerror', (e) => errors.push('pageerror: ' + e.message));
  p.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  await p.goto('http://127.0.0.1:8765/preview.html', { waitUntil: 'networkidle0' });
  await p.evaluate(() => localStorage.clear());
  await p.reload({ waitUntil: 'networkidle0' });
  await p.waitForFunction(() => window.__evochi);
  return p;
}

const click = async (p, k) => { const el = await p.$(`[data-k="${k}"]`); if (!el) throw new Error('missing ' + k); await el.click(); await sleep(350); };
const clean = (p) => p.evaluate(() => {
  document.querySelectorAll('.toasts > *').forEach((t) => t.remove());
  document.querySelectorAll('.card.dev').forEach((t) => t.remove());
  // label the step source the way the phone app does once Apple Health is connected
  const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  while (w.nextNode()) if (w.currentNode.nodeValue.includes('Simulated step device')) w.currentNode.nodeValue = 'Apple Health';
});
const shot = async (p, n, wait = 1000) => { await sleep(wait); await clean(p); await sleep(120); await p.screenshot({ path: `${OUT}/${n}.png` }); console.log('shot', n); };

// A pet that has lived a little: evolved, levelled, dressed, nest decorated, mid-walk today.
async function stage(p, { palette = 'forest', name = 'Pip', evolve = true, steps = [2500, 2500, 500], dress = true } = {}) {
  await p.evaluate(async (o) => {
    const { app, store, G } = window.__evochi;
    let now = store.now();
    store.run((s) => G.startGuest(s, now, 'America/New_York'));
    store.run((s) => G.createPet(s, { name: o.name, paletteId: o.palette, requestId: 'x' }, now));
    store.run((s) => G.setConnection(s, 'demo', now));
    store.run((s) => G.finishOnboarding(s));
    const s0 = structuredClone(store.state); s0.flags.coachDone = true; store.replace(s0);
    app.tab('home');
  }, { palette, name });
  await sleep(600);
  if (evolve) {
    await click(p, 'tab-home');
    await p.evaluate(() => { const { app } = window.__evochi; app.ui.home = { wakeUntil: Date.now() + 1e7 }; });
    await click(p, 'set');
    await click(p, 'dv3');
    await click(p, 'dv2');
    await click(p, 'sback');
    await p.evaluate(() => {
      const { store, G } = window.__evochi;
      store.run((s, n) => G.evolve(s, n), store.now());
    });
    await sleep(300);
  }
  await p.evaluate(async (o) => {
    const { store, G, app } = window.__evochi;
    const run = (f) => store.run((s, n) => f(s, n), store.now());
    run((s, n) => G.grantCoins(s, 1400, n));
    if (o.dress) {
      for (const id of ['leaf_scarf', 'meadow_nest', 'sunlit_flower', 'explorer_lantern', 'golden_crest_crown', 'explorer_hat']) {
        run((s, n) => G.purchase(s, id, 'buy-' + id, n));
      }
      run((s, n) => G.equip(s, 'leaf_scarf', n));
      run((s) => G.placeDecoration(s, 'meadow_nest', 'nest'));
      run((s) => G.placeDecoration(s, 'sunlit_flower', 'left'));
      run((s) => G.placeDecoration(s, 'explorer_lantern', 'right'));
    }
    run((s, n) => G.interact(s, 'pet', n));
    run((s, n) => G.interact(s, 'play', n));
    app.tab('home');
  }, { dress });
  if (steps) {
    await click(p, 'tab-journey');
    for (const n of steps) { await click(p, 'w' + n); await sleep(250); }
  }
  await p.evaluate(() => { const { app } = window.__evochi; app.ui.home = { wakeUntil: Date.now() + 1e7 }; app.tab('home'); });
  await sleep(900);
}

let p = await page();
await stage(p);
await shot(p, 'home', 1500);
await click(p, 'tab-journey');
await shot(p, 'journey');
await click(p, 'tab-shop');
await shot(p, 'market');
await click(p, 'tab-bag');
await shot(p, 'bag');
await click(p, 'tab-evodex');
await shot(p, 'evodex');
await p.close();

// the evolution moment, with a fresh eggling that's ready
p = await page();
await stage(p, { palette: 'ocean', name: 'Bubbles', evolve: false, steps: null, dress: false });
await click(p, 'set');
await click(p, 'dv3');
await click(p, 'sback');
await p.evaluate(() => { const { app } = window.__evochi; app.ui.home = { wakeUntil: Date.now() + 1e7 }; });
await shot(p, 'evolve_ready', 1200);
await click(p, 'evolve');
await shot(p, 'evolve_reveal', 3600);
await p.close();

// the welcome screen
p = await page();
await shot(p, 'welcome', 1500);
await p.close();

console.log('ERRORS', JSON.stringify(errors.slice(0, 20), null, 1));
await b.close();
