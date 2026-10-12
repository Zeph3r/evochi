import chromium from '@sparticuz/chromium';
import puppeteer from 'puppeteer-core';
import fs from 'node:fs';
import path from 'node:path';
const OUT = process.argv[2];
fs.mkdirSync(OUT, { recursive: true });
const b = await puppeteer.launch({ executablePath: await chromium.executablePath(), args: chromium.args, headless: true });
const p = await b.newPage();
await p.setViewport({ width: 2700, height: 1600, deviceScaleFactor: 1 });
p.on('pageerror', (e) => console.log('pageerror', e.message));
p.on('console', (m) => { if (m.type() === 'error') console.log('console', m.text()); });
await p.goto('http://127.0.0.1:8766/ad/social.html', { waitUntil: 'networkidle0' });
await p.evaluate(() => document.fonts.ready);
await p.evaluate(async () => { await Promise.all([...document.images].map((i) => i.decode().catch(() => {}))); });
const ids = await p.evaluate(() => [...document.querySelectorAll('.card')].map((c) => c.id));
for (const id of ids) {
  const el = await p.$('#' + id);
  const png = id.startsWith('pfp') || id.startsWith('hl_');
  await el.screenshot({ path: path.join(OUT, `${id}.${png ? 'png' : 'jpg'}`), type: png ? 'png' : 'jpeg', quality: png ? undefined : 92 });
}
console.log('rendered', ids.length);
await b.close();
