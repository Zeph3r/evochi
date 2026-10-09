// Renders comp.html frame by frame: node ad_render.mjs OUT_DIR [t0 t1] [--preview step]
import chromium from '@sparticuz/chromium';
import puppeteer from 'puppeteer-core';
import fs from 'node:fs';
import path from 'node:path';
const OUT = process.argv[2];
const t0 = process.argv[3] ? +process.argv[3] : 0;
const t1 = process.argv[4] ? +process.argv[4] : null;
const stepArg = process.argv.indexOf('--preview');
const step = stepArg > 0 ? +process.argv[stepArg + 1] : 1;
fs.mkdirSync(OUT, { recursive: true });
const b = await puppeteer.launch({ executablePath: await chromium.executablePath(), args: chromium.args, headless: true });
const p = await b.newPage();
await p.setViewport({ width: 1080, height: 1920, deviceScaleFactor: 1 });
p.on('pageerror', (e) => console.log('pageerror', e.message));
p.on('console', (m) => { if (m.type() === 'error') console.log('console', m.text()); });
await p.goto('http://127.0.0.1:8766/ad/comp.html', { waitUntil: 'networkidle0' });
await p.evaluate(() => document.fonts.ready);
const total = await p.evaluate(() => window.__total);
const FPS = 30;
const end = t1 ?? total;
const first = Math.round(t0 * FPS), last = Math.round(end * FPS);
const started = Date.now();
for (let f = first; f < last; f += step) {
  await p.evaluate((t) => window.seek(t), f / FPS);
  await p.screenshot({ path: path.join(OUT, `f${String(f).padStart(5, '0')}.png`), type: 'png', clip: { x: 0, y: 0, width: 1080, height: 1920 } });
  if ((f - first) % 90 === 0) console.log('frame', f, '/', last, ((Date.now() - started) / 1000).toFixed(0) + 's');
}
await b.close();
console.log('done', last - first, 'frames');
