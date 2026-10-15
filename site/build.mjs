// Builds the Evochi website from src/ + config.json.
//   node build.mjs            -> dist/host      (self-hosted fonts, SEO tags; upload this folder to your web host)
//   node build.mjs artifact   -> dist/artifact  (the preview published as a claude.ai artifact)
// Empty config values render as highlighted placeholders so nothing ships half-filled by accident.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const TARGET = process.argv[2] === 'artifact' ? 'artifact' : 'host';
const OUT = path.join(ROOT, 'dist', TARGET);
const cfg = JSON.parse(fs.readFileSync(path.join(ROOT, 'config.json'), 'utf8'));
cfg.privacyEmail ||= cfg.supportEmail;
cfg.developerName ||= cfg.companyName;
const siteUrl = (cfg.siteUrl || '').replace(/\/+$/, '');

const LABELS = {
  companyName: 'Studio legal name', companyAddress: 'registered address', supportEmail: 'support email',
  privacyEmail: 'privacy email', developerName: 'developer name as shown on Google Play',
  governingLaw: 'country or state', effectiveDate: 'date', minimumAge: 'minimum age', previewUrl: 'preview link',
};
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const fill = (k) => `<span class="fill">[${LABELS[k] || k}]</span>`;
const val = (k) => (cfg[k] !== undefined && cfg[k] !== '' ? esc(cfg[k]) : fill(k));
const email = (k) => {
  if (!cfg[k]) return fill(k);
  // mailto links are unreliable inside the artifact viewer, so the preview shows plain text
  return TARGET === 'host' ? `<a href="mailto:${esc(cfg[k])}">${esc(cfg[k])}</a>` : esc(cfg[k]);
};
const copybox = (k, id) => `<div class="copybox"><code id="${id}">${cfg[k] ? esc(cfg[k]) : `[${LABELS[k]}]`}</code>` +
  `<button class="btn cream sm" type="button" data-copy="${id}">Copy address</button><span class="copied" aria-live="polite"></span></div>`;

const launched = Boolean(cfg.appStoreUrl || cfg.playStoreUrl);
const storeRel = (u) => (u ? ' rel="noopener"' : '');
const BETA = cfg.siteMode === 'beta';
const goal = Number(cfg.waitlistGoal) || 5000;
const spots = Number(cfg.founderSpots) || 1000;

const PAGES = [
  { src: 'index.html', title: BETA ? 'Evochi · Join the beta waitlist' : 'Evochi · A walking pet that grows with every step', artifactTitle: 'Evochi Website',
    desc: BETA ? 'Hatch a voxel lizard, walk to help it grow, and raise it from Eggling to Elder. Join the beta waitlist: pick your egg, and the first 1,000 get the Founder\'s Crown.'
               : 'Hatch a voxel lizard, walk to help it grow, and raise it from Eggling to Elder. A cozy walking pet game for iPhone and Android.' },
  { src: 'privacy.html', title: 'Privacy policy · Evochi', legal: true,
    desc: 'What Evochi collects, why, and the controls you have. Evochi reads only your step count, never sells data and never uses it for ads.' },
  { src: 'terms.html', title: 'Terms of use · Evochi', legal: true, desc: 'The terms for playing Evochi and using this website.' },
  { src: 'support.html', title: 'Support · Evochi', legal: true, nav: 'support',
    desc: 'Fix step syncing, help a sick Evochi, evolve, move to a new phone, or contact the Evochi team.' },
  { src: 'delete-account.html', title: 'Delete your account · Evochi', legal: true,
    desc: 'How to delete your Evochi account and data, with or without the app, and what we keep.' },
  { src: '404.html', title: 'Page not found · Evochi', noindex: true, desc: 'This page could not be found.' },
];

const read = (p) => fs.readFileSync(path.join(ROOT, 'src', p), 'utf8');

function render(tpl, page) {
  const isIndex = page.src === 'index.html';
  const ctx = {
    home: isIndex ? '' : './',
    year: String(new Date().getFullYear()),
    draftBanner: cfg.legalDraft && page.legal
      ? '<div class="draft-banner" role="note"><div class="wrap">Draft for review: fill in the highlighted details in <code>site/config.json</code> and have a lawyer check this page before you publish it.</div></div>'
      : '',
    navSupport: page.nav === 'support' ? ' aria-current="page"' : '',
    appStoreHref: esc(cfg.appStoreUrl || (isIndex ? '#get' : './#get')),
    playStoreHref: esc(cfg.playStoreUrl || (isIndex ? '#get' : './#get')),
    appStoreRel: storeRel(cfg.appStoreUrl), playStoreRel: storeRel(cfg.playStoreUrl),
    appStoreSmall: cfg.appStoreUrl ? 'Download on the' : 'Coming soon to the',
    playStoreSmall: cfg.playStoreUrl ? 'Get it on' : 'Coming soon to',
    supportCopybox: copybox('supportEmail', 'support-email'),
    privacyCopybox: copybox('privacyEmail', 'privacy-email'),
    // beta mode: the waitlist replaces the store buttons
    heroClass: BETA ? ' beta' : '',
    ctaAnchor: BETA ? 'beta' : 'get',
    ctaLabel: BETA ? 'Join the beta' : 'Get Evochi',
    heroTag: BETA ? 'Beta waitlist open' : 'A walking pet game',
    heroHeadline: BETA ? 'Your steps. Your Evochi. Hatch it first.' : 'Every step brings your Evochi to life.',
    heroLede: BETA ? 'A cozy voxel lizard that grows from the steps your phone already counts. Pick your egg, join the waitlist, and help hatch Mochi: at ' + goal.toLocaleString('en-US') + ' sign-ups, beta opens.'
                   : 'Hatch a little voxel lizard, walk to help it grow, and raise it from Eggling to Elder. Evochi turns the steps your phone already counts into XP, coins and evolutions.',
    heroCta: BETA ? read('partials/waitlist.html') : read('partials/stores.html'),
    finalHeadline: BETA ? 'Help hatch Mochi.' : 'Your Eggling is waiting.',
    finalLede: BETA ? 'Every sign-up warms the nest. Bring a friend and you both move up the line.' : 'Download Evochi, hatch your egg and take it on its first walk today.',
    finalCta: BETA ? '<div class="wl-mini" data-wl-mini><span class="num" data-count-mini>—</span><span>of ' + goal.toLocaleString('en-US') + ' signed up</span></div><a class="btn lg" href="#beta">Join the beta waitlist</a>' : read('partials/stores.html'),
    faqBeta: BETA ? '<details class="card" open><summary>When does the beta start, and how do I get in?</summary><div class="answer"><p>Beta opens when the waitlist reaches ' + goal.toLocaleString('en-US') + ' sign-ups. Invites go out in waitlist order, in waves, by email. Bringing a friend with your link moves you both up the line.</p><p>The first ' + spots.toLocaleString('en-US') + ' people on the list get the Founder\'s Crown: a wearable that fits every form, kept forever, and never sold in the Market.</p></div></details>'
                  + '<details class="card"><summary>What do you do with my email?</summary><div class="answer"><p>One message when it\'s your turn, and nothing else. We store your email, the colour you picked and your referral code, nothing more. Unsubscribe from any email, or ask us to delete you from the list, and it\'s gone.</p></div></details>' : '',
    footerBeta: BETA ? ' Beta coming first; stores after.' : '',
    footerBetaLink: BETA ? '<li><a href="' + (isIndex ? '' : './') + '#beta">Join the beta waitlist</a></li>' : '',
    apiBase: TARGET === 'host' ? '/api' : '',
    waitlistGoal: goal.toLocaleString('en-US'),
    founderSpots: spots.toLocaleString('en-US'),
    turnstile: TARGET === 'host' && cfg.turnstileSiteKey ? '<div class="cf-turnstile" data-sitekey="' + esc(cfg.turnstileSiteKey) + '" data-theme="light" data-size="flexible"></div>' : '',
  };
  let out = tpl;
  for (let i = 0; i < 3; i++) out = out.replace(/\{\{>\s*([\w-]+)\s*\}\}/g, (_, n) => read(`partials/${n}.html`));
  for (let i = 0; i < 3; i++) { // a token's value may itself carry tokens (the hero's waitlist partial)
    out = out.replace(/\{\{raw:(\w+)\}\}/g, (_, k) => esc(cfg[k] || ''));
    out = out.replace(/\{\{email:(\w+)\}\}/g, (_, k) => email(k));
    out = out.replace(/\{\{(\w+)\}\}/g, (_, k) => (k in ctx ? ctx[k] : val(k)));
  }
  const left = out.match(/\{\{[^}]*\}\}/);
  if (left) throw new Error(`${page.src}: unresolved token ${left[0]}`);
  return out;
}

const FONTS = [['Nunito', 700], ['Nunito', 800], ['Nunito', 900], ['Lato', 400], ['Lato', 700], ['Lato', 900]];
const GOOGLE_FONTS = '<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>' +
  '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Lato:wght@400;700;900&family=Nunito:wght@700;800;900&display=swap">';

function head(page) {
  const isIndex = page.src === 'index.html';
  const url = siteUrl ? `${siteUrl}/${isIndex ? '' : page.src}` : '';
  const title = TARGET === 'artifact' && isIndex ? page.artifactTitle : page.title;
  const h = [];
  if (!(TARGET === 'artifact' && isIndex)) {
    h.push('<meta charset="utf-8">', '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">');
  }
  h.push(`<title>${esc(title)}</title>`, `<meta name="description" content="${esc(page.desc)}">`);
  if (TARGET === 'host') {
    if (page.noindex) h.push('<meta name="robots" content="noindex">');
    if (url) h.push(`<link rel="canonical" href="${url}">`);
    h.push('<meta name="theme-color" content="#FFF9F0">',
      '<meta property="og:type" content="website">', '<meta property="og:site_name" content="Evochi">',
      `<meta property="og:title" content="${esc(page.title)}">`, `<meta property="og:description" content="${esc(page.desc)}">`,
      '<meta name="twitter:card" content="summary_large_image">');
    if (url) h.push(`<meta property="og:url" content="${url}">`);
    if (siteUrl) h.push(`<meta property="og:image" content="${siteUrl}/assets/img/og-image.jpg">`, '<meta property="og:image:width" content="1200">',
      '<meta property="og:image:height" content="630">', '<meta property="og:image:alt" content="Evochi: an Eggling, a Juvenile and an Elder on grassy steps in a voxel meadow.">');
    if (cfg.appStoreId) h.push(`<meta name="apple-itunes-app" content="app-id=${esc(cfg.appStoreId)}">`);
    h.push('<link rel="icon" href="assets/img/favicon.ico" sizes="any">', '<link rel="icon" type="image/png" sizes="32x32" href="assets/img/favicon-32.png">',
      '<link rel="apple-touch-icon" href="assets/img/apple-touch-icon.png">', '<link rel="manifest" href="site.webmanifest">');
    h.push('<link rel="preload" href="assets/fonts/nunito-latin-900-normal.woff2" as="font" type="font/woff2" crossorigin>',
      '<link rel="preload" href="assets/fonts/lato-latin-400-normal.woff2" as="font" type="font/woff2" crossorigin>');
    if (isIndex) {
      h.push('<link rel="preload" as="image" href="assets/img/hero/hero-1920.webp" imagesrcset="assets/img/hero/hero-1200.webp 1200w, assets/img/hero/hero-1920.webp 1920w, assets/img/hero/hero-2880.webp 2880w" imagesizes="(max-width: 899px) 190vw, 100vw">');
      const ld = { '@context': 'https://schema.org', '@type': 'MobileApplication', name: 'Evochi', operatingSystem: 'iOS, Android',
        applicationCategory: 'GameApplication', description: page.desc, offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' } };
      if (siteUrl) ld.image = `${siteUrl}/assets/img/og-image.jpg`;
      if (cfg.companyName) ld.author = { '@type': 'Organization', name: cfg.companyName };
      h.push(`<script type="application/ld+json">${JSON.stringify(ld)}</script>`);
    }
  } else {
    h.push(GOOGLE_FONTS);
  }
  if (TARGET === 'host' && BETA && cfg.turnstileSiteKey && isIndex) h.push('<script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>');
  h.push('<link rel="stylesheet" href="assets/site.css">');
  return h.join('\n');
}

function copyDir(from, to, filter = () => true) {
  fs.mkdirSync(to, { recursive: true });
  for (const e of fs.readdirSync(from, { withFileTypes: true })) {
    const a = path.join(from, e.name), b = path.join(to, e.name);
    if (e.isDirectory()) copyDir(a, b, filter);
    else if (filter(a)) fs.copyFileSync(a, b);
  }
}

fs.rmSync(OUT, { recursive: true, force: true });
fs.mkdirSync(path.join(OUT, 'assets'), { recursive: true });
copyDir(path.join(ROOT, 'assets', 'img'), path.join(OUT, 'assets', 'img'), (f) => !f.endsWith('sizes.json'));
if (fs.existsSync(path.join(ROOT, 'assets', 'email'))) copyDir(path.join(ROOT, 'assets', 'email'), path.join(OUT, 'assets', 'email'));
fs.copyFileSync(path.join(ROOT, 'assets', 'chirp.mp3'), path.join(OUT, 'assets', 'chirp.mp3'));
let css = read('site.css');
if (TARGET === 'host') {
  copyDir(path.join(ROOT, 'assets', 'fonts'), path.join(OUT, 'assets', 'fonts'));
  const faces = FONTS.map(([f, w]) => `@font-face { font-family: '${f}'; font-weight: ${w}; font-style: normal; font-display: swap; src: url('fonts/${f.toLowerCase()}-latin-${w}-normal.woff2') format('woff2'); }`);
  css = faces.join('\n') + '\n' + css;
}
fs.writeFileSync(path.join(OUT, 'assets', 'site.css'), css);
fs.writeFileSync(path.join(OUT, 'assets', 'site.js'), read('site.js'));

const header = read('partials/header.html');
const footer = read('partials/footer.html');
for (const page of PAGES) {
  const body = render(header + read(`pages/${page.src}`) + footer, page);
  const isIndex = page.src === 'index.html';
  const html = TARGET === 'artifact' && isIndex
    ? `${head(page)}\n${body}` // the artifact host wraps this in its own document skeleton
    : `<!doctype html>\n<html lang="en">\n<head>\n${head(page)}\n</head>\n<body>\n${body}</body>\n</html>\n`;
  fs.writeFileSync(path.join(OUT, page.src), html);
}

if (TARGET === 'host') {
  const pages = PAGES.filter((p) => !p.noindex);
  fs.writeFileSync(path.join(OUT, 'robots.txt'), `User-agent: *\nAllow: /\n${siteUrl ? `Sitemap: ${siteUrl}/sitemap.xml\n` : ''}`);
  if (siteUrl) {
    const today = new Date().toISOString().slice(0, 10);
    fs.writeFileSync(path.join(OUT, 'sitemap.xml'), `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n` +
      pages.map((p) => `  <url><loc>${siteUrl}/${p.src === 'index.html' ? '' : p.src}</loc><lastmod>${today}</lastmod></url>`).join('\n') + '\n</urlset>\n');
  }
  fs.writeFileSync(path.join(OUT, 'site.webmanifest'), JSON.stringify({
    name: 'Evochi', short_name: 'Evochi', start_url: './', display: 'browser', background_color: '#FFF9F0', theme_color: '#F4B84E',
    icons: [{ src: 'assets/img/icon-512.png', sizes: '512x512', type: 'image/png' }, { src: 'assets/img/apple-touch-icon.png', sizes: '180x180', type: 'image/png' }],
  }, null, 1));
}

const files = [];
(function walk(d) {
  for (const e of fs.readdirSync(d, { withFileTypes: true })) {
    const p = path.join(d, e.name);
    if (e.isDirectory()) walk(p); else files.push(path.relative(OUT, p));
  }
})(OUT);
fs.writeFileSync(path.join(ROOT, 'dist', `${TARGET}-files.json`), JSON.stringify(files.sort(), null, 1));
console.log(`${TARGET}: ${files.length} files -> ${path.relative(process.cwd(), OUT)}`);
