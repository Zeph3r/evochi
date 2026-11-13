// Records the live pet lab (a web build of lib/main_lab.dart, served at BASE) showing a few personalities
// meeting the same things, as videos and stills in OUT. Used by .github/workflows/live-lab.yml.
//   node record_lab.cjs BASE OUT
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const [BASE, OUT] = process.argv.slice(2);
fs.mkdirSync(OUT, { recursive: true });
const SHOWS = [
  // a curious one with no courage: it creeps up on something new and bolts, a little less each time
  ['timid-explorer', 'seed=7&genes=curiosity:95,courage:6,feistiness:10,energy:55,sociability:45&demo=2:object,22:object,38:visitor', 50],
  // curious, brave and feisty: it stalks and pounces
  ['feisty-pouncer', 'seed=11&genes=curiosity:85,courage:88,feistiness:92,energy:80,expressiveness:70&demo=2:object,16:object,30:visitor', 44],
  // a friendly bubbly one: greets the visitor, loves being petted, shows off
  ['friendly-bubbly', 'seed=21&genes=sociability:95,courage:60,expressiveness:90,energy:70&demo=2:visitor,16:pet,24:food,32:pet', 42],
  // sleepy and greedy: food first, then a nap
  ['sleepy-greedy', 'seed=33&genes=energy:6,appetite:94,curiosity:30,expressiveness:20&demo=2:food,20:object,30:pet', 40],
];

(async () => {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  for (const [name, q, secs] of SHOWS) {
    const ctx = await b.newContext({ viewport: { width: 430, height: 900 }, recordVideo: { dir: OUT, size: { width: 430, height: 900 } } });
    const p = await ctx.newPage();
    p.on('console', (m) => { if (m.type() === 'error') console.log(name, 'console:', m.text()); });
    await p.goto(`${BASE}/?${q}`, { waitUntil: 'load' });
    await p.waitForSelector('flt-glass-pane, flutter-view', { state: 'attached', timeout: 120000 });
    for (let t = 0; t < secs; t += 10) {
      await p.waitForTimeout(10000);
      await p.screenshot({ path: path.join(OUT, `${name}-${String(t + 10).padStart(2, '0')}s.png`) });
    }
    const v = p.video();
    await ctx.close();
    fs.renameSync(await v.path(), path.join(OUT, `${name}.webm`));
    console.log('recorded', name);
  }
  await b.close();
})().catch((e) => { console.error(e); process.exit(1); });
