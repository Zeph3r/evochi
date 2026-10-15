// Builds the Evochi email kit.
//   node emails/build.mjs
// Writes:
//   emails/dist/html/<name>.html      ready-to-paste HTML, filled with the sample data, images hosted on evochigame.com
//   emails/dist/text/<name>.txt       plain-text twin
//   emails/dist/subjects.txt          subject lines and preheaders for every template
//   emails/dist/preview/              a gallery (index.html) that previews every template offline
//   functions/api/_emails.js          the transactional templates compiled for the waitlist API
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { render, fmt, COLOUR_NAMES } from './render.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SITE = path.join(HERE, '..');
const DIST = path.join(HERE, 'dist');
const cfg = JSON.parse(fs.readFileSync(path.join(HERE, 'emails.json'), 'utf8'));
const layout = fs.readFileSync(path.join(HERE, 'layout.html'), 'utf8');
const siteCfg = JSON.parse(fs.readFileSync(path.join(SITE, 'config.json'), 'utf8'));
if (siteCfg.siteUrl) cfg.defaults.siteUrl = siteCfg.siteUrl.replace(/\/+$/, '');
if (!cfg.defaults.assetBase) cfg.defaults.assetBase = cfg.defaults.siteUrl + '/assets/email';
if (siteCfg.waitlistGoal) cfg.defaults.goal = siteCfg.waitlistGoal;
if (siteCfg.companyName && !cfg.defaults.companyLine) cfg.defaults.companyLine = siteCfg.companyName + (siteCfg.companyAddress ? ', ' + siteCfg.companyAddress : '');

/** Fills in the derived tokens every template can use (formatted numbers, colour names, links). */
export function prepare(data, defaults = cfg.defaults) {
  const d = { ...defaults, ...data };
  d.goal = Number(d.goal || defaults.goal || 5000);
  d.goalFmt = fmt(d.goal);
  if (d.count != null) { d.countFmt = fmt(d.count); d.pct = Math.max(2, Math.min(100, Math.round((100 * d.count) / d.goal))); }
  if (d.position != null) d.positionFmt = fmt(d.position);
  if (d.colour) d.colourName = COLOUR_NAMES[d.colour] || d.colour;
  if (d.code) {
    d.refLink = d.refLink || `${d.siteUrl}/?ref=${d.code}`;
    d.unsubLink = d.unsubLink || `${d.siteUrl}/api/unsubscribe?code=${d.code}`;
  }
  if (d.refLink) d.refLinkShort = d.refLink.replace(/^https?:\/\//, '');
  if (d.referrals != null) d.friendWord = Number(d.referrals) === 1 ? 'friend' : 'friends';
  if (d.heroImage && !/^https?:\/\//.test(d.heroImage)) d.heroImage = `${d.assetBase}/${d.heroImage}`;
  return d;
}

export function compile(name) {
  const t = cfg.templates[name];
  const body = fs.readFileSync(path.join(HERE, 'templates', `${name}.html`), 'utf8');
  const text = fs.readFileSync(path.join(HERE, 'templates', `${name}.txt`), 'utf8');
  return { ...t, body, text, html: layout.replace('{{{body}}}', body) };
}

export function renderEmail(name, data) {
  const c = compile(name);
  const d = prepare(data);
  const subject = render(c.subject, d);
  d.subject = subject;
  d.preheader = render(c.preheader, d);
  return { subject, html: render(c.html, d), text: render(c.text, d).replace(/\n{3,}/g, '\n\n') };
}

function main() {
  fs.rmSync(DIST, { recursive: true, force: true });
  for (const sub of ['html', 'text', 'preview/img']) fs.mkdirSync(path.join(DIST, sub), { recursive: true });
  for (const f of fs.readdirSync(path.join(SITE, 'assets', 'email'))) fs.copyFileSync(path.join(SITE, 'assets', 'email', f), path.join(DIST, 'preview', 'img', f));

  const subjects = ['EVOCHI EMAIL SUBJECTS AND PREHEADERS', '(filled with the sample data; the {{tokens}} version is in emails.json)', ''];
  const cards = [];
  for (const name of Object.keys(cfg.templates)) {
    const t = cfg.templates[name];
    const out = renderEmail(name, t.sample);
    fs.writeFileSync(path.join(DIST, 'html', `${name}.html`), out.html);
    fs.writeFileSync(path.join(DIST, 'text', `${name}.txt`), out.text);
    // offline preview: same email, images from the local img/ folder
    const prev = renderEmail(name, { ...t.sample, assetBase: 'img' });
    fs.writeFileSync(path.join(DIST, 'preview', `${name}.html`), prev.html);
    fs.writeFileSync(path.join(DIST, 'preview', `${name}.txt`), prev.text);
    subjects.push(`## ${t.name}  (${name})`, `Subject:   ${out.subject}`, `Preheader: ${render(t.preheader, prepare({ ...t.sample, subject: out.subject }))}`);
    for (const a of t.altSubjects || []) subjects.push(`Alt:       ${render(a, prepare(t.sample))}`);
    subjects.push(`Sent:      ${t.sent}`, '');
    cards.push({ name, title: t.name, subject: out.subject, preheader: render(t.preheader, prepare({ ...t.sample, subject: out.subject })), sent: t.sent, when: t.when, alts: (t.altSubjects || []).map((a) => render(a, prepare(t.sample))), tokens: t.tokens, text: prev.text });
  }
  fs.writeFileSync(path.join(DIST, 'subjects.txt'), subjects.join('\n'));
  fs.writeFileSync(path.join(DIST, 'preview', 'index.html'), gallery(cards));
  fs.writeFileSync(path.join(DIST, 'preview', 'artifact.html'), galleryArtifact(cards.map((c) => ({ ...c, html: fs.readFileSync(path.join(DIST, 'preview', `${c.name}.html`), 'utf8') }))));

  // the transactional templates, compiled for Cloudflare Pages Functions
  const renderSrc = fs.readFileSync(path.join(HERE, 'render.js'), 'utf8');
  const tx = {};
  for (const name of ['waitlist-welcome', 'referral-moved-up']) {
    const c = compile(name);
    tx[name] = { subject: c.subject, preheader: c.preheader, html: c.html, text: c.text };
  }
  const js = `// GENERATED by emails/build.mjs. Edit emails/templates/* and emails.json, then run: node emails/build.mjs\n` +
    renderSrc.replace(/^export /gm, '') + '\n' +
    `const TEMPLATES = ${JSON.stringify(tx)};\n` +
    `export function prepare(data) {\n` +
    `  const d = { ...data };\n` +
    `  d.goal = Number(d.goal || 5000); d.goalFmt = fmt(d.goal);\n` +
    `  if (d.count != null) { d.countFmt = fmt(d.count); d.pct = Math.max(2, Math.min(100, Math.round((100 * d.count) / d.goal))); }\n` +
    `  if (d.position != null) d.positionFmt = fmt(d.position);\n` +
    `  if (d.colour) d.colourName = COLOUR_NAMES[d.colour] || d.colour;\n` +
    `  if (d.code) { d.refLink = d.refLink || d.siteUrl + '/?ref=' + d.code; d.unsubLink = d.unsubLink || d.siteUrl + '/api/unsubscribe?code=' + d.code; }\n` +
    `  if (d.refLink) d.refLinkShort = d.refLink.replace(/^https?:\\/\\//, '');\n` +
    `  if (d.referrals != null) d.friendWord = Number(d.referrals) === 1 ? 'friend' : 'friends';\n` +
    `  return d;\n` +
    `}\n` +
    `/** renderEmail('waitlist-welcome', { siteUrl, assetBase, signoff, position, colour, founder, code, referrals, count, goal }) -> { subject, html, text } */\n` +
    `export function renderEmail(name, data) {\n` +
    `  const t = TEMPLATES[name]; if (!t) throw new Error('unknown email ' + name);\n` +
    `  const d = prepare(data); d.subject = render(t.subject, d); d.preheader = render(t.preheader, d);\n` +
    `  return { subject: d.subject, html: render(t.html, d), text: render(t.text, d).replace(/\\n{3,}/g, '\\n\\n') };\n` +
    `}\n`;
  fs.writeFileSync(path.join(SITE, 'functions', 'api', '_emails.js'), js);
  console.log('email kit built:', Object.keys(cfg.templates).length, 'templates ->', path.relative(process.cwd(), DIST), 'and functions/api/_emails.js');
}

function gallery(cards) {
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
  const nav = cards.map((c, i) => `<button class="nav${i === 0 ? ' on' : ''}" data-i="${i}"><b>${String(i + 1).padStart(2, '0')}</b> ${esc(c.title)}</button>`).join('');
  const data = JSON.stringify(cards);
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Evochi Email Kit</title>
<link href="https://fonts.googleapis.com/css2?family=Nunito:wght@800;900&family=Lato:wght@400;700&display=swap" rel="stylesheet">
<style>
  :root { --ink: #3B2923; --ink-700: #684C3C; --ink-500: #8E7462; --cream: #FFF9F0; --cream-200: #F4E2CD; --parch: #EED9C2; --line: #C9A78C; --gold: #F4B84E; --gold-700: #C8832C; --gold-100: #FFE5A2; --meadow: #477B3A; --meadow-100: #E5F2CF; }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--cream-200); color: var(--ink); font: 16px/1.5 Lato, 'Helvetica Neue', Arial, sans-serif; }
  header { display: flex; align-items: center; gap: 16px; padding: 16px 24px; background: var(--cream); border-bottom: 3px solid var(--line); }
  header img { height: 40px; }
  header h1 { margin: 0; font: 900 22px Nunito, sans-serif; }
  header p { margin: 0; color: var(--ink-500); font-size: 14px; }
  .app { display: grid; grid-template-columns: 280px 1fr; min-height: calc(100vh - 76px); }
  aside { background: var(--cream); border-right: 3px solid var(--line); padding: 16px 12px; }
  .nav { display: block; width: 100%; text-align: left; margin: 0 0 6px; padding: 12px 14px; border: 2px solid transparent; border-radius: 14px; background: transparent; font: 700 15px Lato, sans-serif; color: var(--ink-700); cursor: pointer; }
  .nav b { font: 900 13px Nunito, sans-serif; color: var(--gold-700); margin-right: 6px; }
  .nav:hover { background: #F8EBDD; }
  .nav.on { background: var(--gold-100); border-color: #E3A64A; color: var(--ink); }
  main { padding: 24px; display: grid; grid-template-columns: minmax(0, 640px) minmax(280px, 1fr); gap: 24px; align-items: start; }
  .frame { background: var(--cream); border: 3px solid var(--line); border-radius: 22px; overflow: hidden; }
  .bar { display: flex; gap: 8px; align-items: center; padding: 10px 14px; border-bottom: 2px solid #E3CBB1; background: #F8EBDD; font-size: 13px; color: var(--ink-500); }
  .bar button { border: 2px solid var(--line); background: var(--cream); border-radius: 999px; padding: 4px 12px; font: 700 13px Lato, sans-serif; color: var(--ink-700); cursor: pointer; }
  .bar button.on { background: var(--gold-100); border-color: #E3A64A; color: var(--ink); }
  iframe { display: block; width: 100%; height: 1500px; border: 0; background: var(--cream-200); transition: width .2s; margin: 0 auto; }
  .frame.phone iframe { width: 390px; }
  pre.text { margin: 0; padding: 20px; white-space: pre-wrap; font: 14px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace; color: var(--ink); background: var(--cream); min-height: 600px; display: none; }
  .frame.text pre.text { display: block; } .frame.text iframe { display: none; }
  .info { background: var(--cream); border: 3px solid var(--line); border-radius: 22px; padding: 22px; position: sticky; top: 16px; }
  .info h2 { margin: 0 0 4px; font: 900 24px Nunito, sans-serif; }
  .k { margin: 16px 0 4px; font: 900 12px Nunito, sans-serif; letter-spacing: .08em; text-transform: uppercase; color: var(--ink-500); }
  .subj { font: 900 17px/1.35 Nunito, sans-serif; } .pre { color: var(--ink-700); font-size: 15px; }
  .alts { margin: 0; padding-left: 18px; color: var(--ink-700); font-size: 14px; } .alts li { margin: 3px 0; }
  .tok { font-size: 13px; color: var(--ink-700); margin: 0; } .tok b { color: var(--ink); font-family: ui-monospace, Menlo, monospace; font-weight: 700; }
  .tok div { margin: 4px 0; }
  .note { background: var(--meadow-100); border: 2px solid #B7D98B; color: #2F5A27; border-radius: 14px; padding: 12px 14px; font-size: 14px; }
  @media (max-width: 1100px) { main { grid-template-columns: 1fr; } .info { position: static; } }
  @media (max-width: 760px) { .app { grid-template-columns: 1fr; } aside { border-right: 0; border-bottom: 3px solid var(--line); display: flex; flex-wrap: wrap; gap: 6px; } .nav { width: auto; margin: 0; } main { padding: 16px; } }
</style></head>
<body>
<header><img src="img/wordmark.png" alt="Evochi"><div><h1>Email kit</h1><p>${cards.length} templates, filled with sample data. Pick one on the left; the panel on the right has the subject line, when to send it, and the merge fields.</p></div></header>
<div class="app">
  <aside>${nav}</aside>
  <main>
    <div class="frame" id="frame">
      <div class="bar"><span id="fname"></span><span style="flex:1"></span><button id="b-desk" class="on">Desktop</button><button id="b-phone">Phone</button><button id="b-text">Plain text</button></div>
      <iframe id="view" title="Email preview"></iframe>
      <pre class="text" id="text"></pre>
    </div>
    <div class="info" id="info"></div>
  </main>
</div>
<script>
const CARDS = ${data};
const $ = (s) => document.querySelector(s);
let mode = 'desk';
function show(i) {
  const c = CARDS[i];
  document.querySelectorAll('.nav').forEach((b, j) => b.classList.toggle('on', j === i));
  $('#view').src = c.name + '.html';
  $('#text').textContent = c.text;
  $('#fname').textContent = c.name + '.html';
  const esc = (s) => String(s).replace(/[&<>]/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[ch]);
  $('#info').innerHTML = '<h2>' + esc(c.title) + '</h2>' +
    '<div class="k">Subject</div><div class="subj">' + esc(c.subject) + '</div>' +
    '<div class="k">Preheader (the grey preview text in the inbox)</div><div class="pre">' + esc(c.preheader) + '</div>' +
    (c.alts.length ? '<div class="k">Alternative subjects to test</div><ul class="alts">' + c.alts.map((a) => '<li>' + esc(a) + '</li>').join('') + '</ul>' : '') +
    '<div class="k">How it\\'s sent</div><div class="note">' + esc(c.sent) + '</div>' +
    '<div class="k">Why it exists</div><p class="tok" style="font-size:14px">' + esc(c.when) + '</p>' +
    '<div class="k">Merge fields</div><div class="tok">' + Object.entries(c.tokens).map(([k, v]) => '<div><b>{{' + esc(k) + '}}</b> ' + esc(v) + '</div>').join('') + '</div>';
  try { localStorage.setItem('evochi.emailkit', String(i)); } catch (e) {}
}
document.querySelectorAll('.nav').forEach((b) => b.addEventListener('click', () => show(+b.dataset.i)));
function setMode(m) { mode = m; $('#frame').className = 'frame' + (m === 'phone' ? ' phone' : m === 'text' ? ' text' : ''); for (const k of ['desk', 'phone', 'text']) $('#b-' + k).classList.toggle('on', k === m); }
$('#b-desk').onclick = () => setMode('desk'); $('#b-phone').onclick = () => setMode('phone'); $('#b-text').onclick = () => setMode('text');
let start = 0; try { start = Math.min(CARDS.length - 1, +(localStorage.getItem('evochi.emailkit') || 0)) || 0; } catch (e) {}
show(start);
</script>
</body></html>`;
}

function galleryArtifact(cards) {
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
  const nav = cards.map((c, i) => `<button class="nav${i === 0 ? ' on' : ''}" data-i="${i}" id="nav-${c.name}"><b>${String(i + 1).padStart(2, '0')}</b><span>${esc(c.title)}</span><small>${esc(c.sent.split(',')[0].split('.')[0])}</small></button>`).join('');
  const data = JSON.stringify(cards).replace(/<\/script/gi, '<\\/script');
  return `<title>Evochi Email Kit</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link href="https://fonts.googleapis.com/css2?family=Nunito:wght@800;900&family=Lato:wght@400;700&display=swap" rel="stylesheet">
<style>
  /* Layout: a sidebar of the eight emails, the rendered email in the middle, and a notes panel (subject, timing, merge fields) on the right; stacks to one column on phones. */
  :root { --bg: #F4E2CD; --panel: #FFF9F0; --panel-2: #F8EBDD; --line: #C9A78C; --line-2: #E3CBB1; --ink: #3B2923; --ink-2: #684C3C; --ink-3: #8E7462; --gold: #F4B84E; --gold-2: #FFE5A2; --gold-line: #E3A64A; --gold-deep: #C8832C; --meadow: #477B3A; --meadow-2: #E5F2CF; --meadow-line: #B7D98B;
    --display: 'Nunito', 'Trebuchet MS', 'Segoe UI', Arial, sans-serif; --body: 'Lato', 'Helvetica Neue', Helvetica, Arial, sans-serif; --mono: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
  @media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg: #241C18; --panel: #2F2621; --panel-2: #382D27; --line: #5C4A3E; --line-2: #4A3B32; --ink: #FFF0DE; --ink-2: #E3CBB1; --ink-3: #B59D88; --gold: #F4B84E; --gold-2: #5C4522; --gold-line: #C8832C; --gold-deep: #F4B84E; --meadow: #B7D98B; --meadow-2: #2E3F25; --meadow-line: #477B3A; color-scheme: dark; } }
  :root[data-theme="dark"] { --bg: #241C18; --panel: #2F2621; --panel-2: #382D27; --line: #5C4A3E; --line-2: #4A3B32; --ink: #FFF0DE; --ink-2: #E3CBB1; --ink-3: #B59D88; --gold: #F4B84E; --gold-2: #5C4522; --gold-line: #C8832C; --gold-deep: #F4B84E; --meadow: #B7D98B; --meadow-2: #2E3F25; --meadow-line: #477B3A; color-scheme: dark; }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--ink); font: 16px/1.5 var(--body); }
  .top { display: flex; align-items: center; gap: 16px; flex-wrap: wrap; padding-block: 16px; padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); background: var(--panel); border-bottom: 3px solid var(--line); }
  .top img { height: 38px; width: auto; }
  .top h1 { margin: 0; font: 900 22px/1.2 var(--display); text-wrap: balance; }
  .top p { margin: 0; color: var(--ink-3); font-size: 14px; max-width: 70ch; }
  .app { display: grid; grid-template-columns: 290px minmax(0, 1fr); align-items: start; }
  aside { background: var(--panel); border-right: 3px solid var(--line); padding-block: 14px; padding-left: max(12px, env(safe-area-inset-left, 0px)); padding-right: 12px; position: sticky; top: 0; max-height: 100vh; overflow: auto; }
  .nav { display: grid; grid-template-columns: 34px 1fr; column-gap: 8px; align-items: center; width: 100%; text-align: left; margin: 0 0 6px; padding: 10px 12px; border: 2px solid transparent; border-radius: 14px; background: transparent; font: 700 15px/1.25 var(--body); color: var(--ink-2); cursor: pointer; }
  .nav b { grid-row: 1 / 3; font: 900 14px var(--display); color: var(--gold-deep); font-variant-numeric: tabular-nums; }
  .nav small { font: 12px/1.3 var(--body); color: var(--ink-3); }
  .nav:hover { background: var(--panel-2); }
  .nav.on { background: var(--gold-2); border-color: var(--gold-line); color: var(--ink); }
  .nav:focus-visible { outline: 3px solid var(--gold-line); outline-offset: 2px; }
  main { display: grid; grid-template-columns: minmax(0, 660px) minmax(280px, 1fr); gap: 22px; align-items: start; padding-block: 22px; padding-left: 22px; padding-right: max(22px, env(safe-area-inset-right, 0px)); min-width: 0; }
  .frame { background: var(--panel); border: 3px solid var(--line); border-radius: 22px; overflow: hidden; min-width: 0; }
  .bar { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; padding: 10px 14px; border-bottom: 2px solid var(--line-2); background: var(--panel-2); font: 13px var(--mono); color: var(--ink-3); }
  .bar .sp { flex: 1; }
  .bar button { border: 2px solid var(--line); background: var(--panel); border-radius: 999px; padding: 4px 12px; font: 700 13px var(--body); color: var(--ink-2); cursor: pointer; }
  .bar button.on { background: var(--gold-2); border-color: var(--gold-line); color: var(--ink); }
  .bar button:focus-visible { outline: 3px solid var(--gold-line); outline-offset: 2px; }
  .view { display: flex; justify-content: center; background: #F4E2CD; }
  iframe { display: block; width: 100%; max-width: 100%; height: 1560px; border: 0; background: #F4E2CD; }
  .frame.phone iframe { width: 390px; }
  pre.text { margin: 0; padding: 20px; white-space: pre-wrap; word-break: break-word; font: 14px/1.6 var(--mono); color: var(--ink); background: var(--panel); min-height: 500px; display: none; }
  .frame.text pre.text { display: block; } .frame.text .view { display: none; }
  .info { background: var(--panel); border: 3px solid var(--line); border-radius: 22px; padding: 22px; min-width: 0; }
  .info h2 { margin: 0 0 4px; font: 900 24px/1.2 var(--display); text-wrap: balance; }
  .k { margin: 16px 0 4px; font: 900 12px var(--display); letter-spacing: .08em; text-transform: uppercase; color: var(--ink-3); }
  .subj { font: 900 17px/1.35 var(--display); }
  .pre { color: var(--ink-2); font-size: 15px; }
  .alts { margin: 0; padding-left: 18px; color: var(--ink-2); font-size: 14px; } .alts li { margin: 3px 0; }
  .tok { font-size: 13px; color: var(--ink-2); margin: 0; } .tok b { color: var(--ink); font-family: var(--mono); font-weight: 700; } .tok div { margin: 4px 0; }
  .note { background: var(--meadow-2); border: 2px solid var(--meadow-line); color: var(--meadow); border-radius: 14px; padding: 12px 14px; font-size: 14px; }
  .copy { margin-top: 14px; display: inline-flex; align-items: center; gap: 8px; border: 2px solid var(--line); background: var(--panel-2); border-radius: 999px; padding: 6px 14px; font: 700 13px var(--body); color: var(--ink-2); cursor: pointer; }
  .copy:focus-visible { outline: 3px solid var(--gold-line); outline-offset: 2px; }
  @media (max-width: 1100px) { main { grid-template-columns: 1fr; } }
  @media (max-width: 760px) { .app { grid-template-columns: 1fr; } aside { position: static; max-height: none; border-right: 0; border-bottom: 3px solid var(--line); padding-right: max(12px, env(safe-area-inset-right, 0px)); } .nav { margin-bottom: 4px; } main { padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); } .frame.phone iframe { width: 100%; } }
  @media (prefers-reduced-motion: no-preference) { .nav, .bar button { transition: background .15s, border-color .15s; } }
</style>
<header class="top"><img src="img/wordmark.png" alt="Evochi"><div><h1>Email kit</h1><p>${cards.length} emails with sample data. Pick one on the left. The panel on the right has the subject line, when it goes out, and the merge fields.</p></div></header>
<div class="app">
  <aside>${nav}</aside>
  <main>
    <div class="frame" id="frame">
      <div class="bar"><span id="fname"></span><span class="sp"></span><button id="b-desk" class="on">Desktop</button><button id="b-phone">Phone</button><button id="b-text">Plain text</button></div>
      <div class="view"><iframe id="view" title="Email preview"></iframe></div>
      <pre class="text" id="text"></pre>
    </div>
    <div class="info" id="info"></div>
  </main>
</div>
<script>
const CARDS = ${data};
const $ = (s) => document.querySelector(s);
const esc = (s) => String(s).replace(/[&<>]/g, (ch) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' })[ch]);
let cur = 0;
function show(i) {
  cur = i; const c = CARDS[i];
  document.querySelectorAll('.nav').forEach((b, j) => b.classList.toggle('on', j === i));
  $('#view').srcdoc = c.html;
  $('#text').textContent = c.text;
  $('#fname').textContent = c.name + '.html';
  $('#info').innerHTML = '<h2>' + esc(c.title) + '</h2>' +
    '<div class="k">Subject</div><div class="subj">' + esc(c.subject) + '</div>' +
    '<div class="k">Preheader (the grey preview text in the inbox)</div><div class="pre">' + esc(c.preheader) + '</div>' +
    (c.alts.length ? '<div class="k">Alternative subjects to test</div><ul class="alts">' + c.alts.map((a) => '<li>' + esc(a) + '</li>').join('') + '</ul>' : '') +
    '<div class="k">How it goes out</div><div class="note">' + esc(c.sent) + '</div>' +
    '<div class="k">Why it exists</div><p class="tok" style="font-size:14px">' + esc(c.when) + '</p>' +
    '<div class="k">Merge fields</div><div class="tok">' + Object.entries(c.tokens).map(([k, v]) => '<div><b>{{' + esc(k) + '}}</b> ' + esc(v) + '</div>').join('') + '</div>' +
    '<button class="copy" id="copy-html">Copy this email\\'s HTML</button> <button class="copy" id="copy-subj">Copy subject</button>';
  $('#copy-html').onclick = () => copyText(c.html, $('#copy-html'), 'HTML copied');
  $('#copy-subj').onclick = () => copyText(c.subject, $('#copy-subj'), 'Subject copied');
  try { localStorage.setItem('evochi.emailkit', String(i)); } catch (e) {}
  if (history.replaceState) history.replaceState(null, '', '#' + c.name);
}
function copyText(t, btn, done) {
  const label = btn.textContent;
  navigator.clipboard.writeText(t).then(() => { btn.textContent = done; setTimeout(() => { btn.textContent = label; }, 1600); }).catch(() => { btn.textContent = 'Select the text below and copy it'; $('#frame').className = 'frame text'; setMode('text'); setTimeout(() => { btn.textContent = label; }, 2500); });
}
document.querySelectorAll('.nav').forEach((b) => b.addEventListener('click', () => show(+b.dataset.i)));
function setMode(m) { $('#frame').className = 'frame' + (m === 'phone' ? ' phone' : m === 'text' ? ' text' : ''); for (const k of ['desk', 'phone', 'text']) $('#b-' + k).classList.toggle('on', k === m); }
$('#b-desk').onclick = () => setMode('desk'); $('#b-phone').onclick = () => setMode('phone'); $('#b-text').onclick = () => setMode('text');
let start = 0;
const h = (location.hash || '').slice(1); const hi = CARDS.findIndex((c) => c.name === h); if (hi >= 0) start = hi;
else { try { start = Math.min(CARDS.length - 1, +(localStorage.getItem('evochi.emailkit') || 0)) || 0; } catch (e) {} }
show(start);
</script>`;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) main();
