// Screenshots of the website's 3D world (scene3d.js), from a build of the site (node site/build.mjs host).
//   node shoot_world.cjs check OUT_DIR      the page at desktop and phone sizes, scrolled to each chapter
//   node shoot_world.cjs stills OUT_DIR     the posters shown before the world loads (and where WebGL is missing),
//                                           the Briarback stills for the lore cards, and the social card's backdrop
// The world is held with ?world=<chapter> or ?world=snap (no easing), so a slow software renderer frames it right.
const { chromium } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..', 'site', 'dist', 'host');
const [mode, OUT] = process.argv.slice(2);
fs.mkdirSync(OUT, { recursive: true });
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.webp': 'image/webp',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.gz': 'application/gzip', '.woff2': 'font/woff2', '.mp3': 'audio/mpeg', '.ico': 'image/x-icon' };
const server = http.createServer((q, r) => {
  let f = path.join(ROOT, decodeURIComponent(q.url.split('?')[0]));
  if (f.endsWith('/')) f += 'index.html';
  fs.readFile(f, (e, b) => { if (e) { r.writeHead(404); r.end(); return; } r.writeHead(200, { 'content-type': TYPES[path.extname(f)] || 'application/octet-stream' }); r.end(b); });
}).listen(8791);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const HIDE = 'main, .site-head, .site-foot, footer, .world-fade { visibility: hidden !important; } html { scrollbar-width: none; }';

(async () => {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const errors = [];
  async function open(w, h, dpr, q, mobile = false) {
    const p = await b.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: dpr, isMobile: mobile, hasTouch: mobile });
    p.on('pageerror', (e) => errors.push(`${w}x${h} pageerror: ${e.message}`));
    p.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') errors.push(`${w}x${h} ${m.type()}: ${m.text()}`); });
    await p.goto(`http://127.0.0.1:8791/index.html?world=${q}`, { waitUntil: 'load' });
    await p.waitForSelector('.world.live, .world.no-3d', { state: 'attached', timeout: 120000 });
    return p;
  }
  if (mode === 'check') {
    for (const [w, h, dpr, tag, mob] of [[1440, 900, 1, 'desk', false], [390, 844, 2, 'phone', true]]) {
      if (process.env.ONLY && process.env.ONLY !== tag) continue;
      const p = await open(w, h, dpr, 'snap', mob);
      await sleep(1500);
      await p.screenshot({ path: `${OUT}/${tag}-0-hero.png` });
      const n = await p.$$eval('[data-chapter]', (els) => els.length);
      for (let i = 0; i < n; i++) {
        await p.evaluate((i) => { const el = document.querySelector(`[data-chapter="${i}"] .lore-card`); scrollTo(0, el.getBoundingClientRect().top + scrollY - (innerHeight - el.offsetHeight) / 2); }, i);
        await sleep(i === 2 ? 4000 : 1800);      // the Briarback loads round chapter III
        await p.screenshot({ path: `${OUT}/${tag}-${i + 1}-chapter.png` });
      }
      for (const id of ['personality', 'family']) {
        await p.evaluate((id) => document.getElementById(id).scrollIntoView(), id);
        await sleep(900);
        await p.screenshot({ path: `${OUT}/${tag}-${id}.png` });
      }
      await p.close();
    }
  } else {
    const shots = [
      ['poster-wide', 1920, 1080, 1, '0.001'], ['poster-tall', 430, 932, 2, '0.001'], ['og-world', 1200, 630, 1, '0.001'],
      ['briarback-hollow', 900, 760, 1, '4.5'], ['briarback-restored', 900, 760, 1, '5.6'],
    ];
    for (const [name, w, h, dpr, q] of shots) {
      const p = await open(w, h, dpr, q);
      await p.addStyleTag({ content: HIDE });
      await sleep(q > 3 ? 6000 : 2500);
      await p.screenshot({ path: `${OUT}/${name}.png` });
      console.log('shot', name);
      await p.close();
    }
  }
  console.log(errors.length ? errors.join('\n') : 'no console errors');
  await b.close();
  server.close();
})().catch((e) => { console.error(e); process.exit(1); });
