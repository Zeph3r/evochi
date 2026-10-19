// S00 Splash / restore, then hand off to the router.
import './styles.css';
import './kit.css';
import { Store } from './core/store.js';
import { App } from './core/app.js';
import { loadManifest, loadImage, manifest, preloadPet } from './ui/assets.js';
import { welcome, create, connect, goal, awakening } from './screens/onboarding.js';
import { home } from './screens/home.js';
import { inspect, evolveScreen } from './screens/pet.js';
import { journey } from './screens/journey.js';
import { bag } from './screens/bag.js';
import { shop } from './screens/shop.js';
import { evodex } from './screens/evodex.js';
import { settings } from './screens/settings.js';
import { village, place } from './screens/village.js';
import { homemap, garden, cottage, station, skills } from './screens/homeland.js';
import { guild, trailplace, prep, travel, encounter } from './screens/trails.js';
import * as G from './game/state.js';
import * as Q from './game/story.js';
import { CloudSave } from './core/cloud.js';

const SCREENS = { welcome, create, connect, goal, awakening, home, inspect, evolve: evolveScreen, journey, bag, shop, evodex, settings, village, place, homemap, garden, cottage, station, skills, guild, trailplace, prep, travel, encounter };

async function boot(hotData = {}) {
  const root = document.getElementById('app');
  const bar = document.getElementById('splash-bar');
  const setP = (p) => bar && (bar.style.width = Math.round(p * 100) + '%');
  try {
    await loadManifest();
    setP(0.2);
    const store = new Store();
    // a live republish hands back the in-memory save so nothing is lost mid-session
    if (hotData && hotData.save) {
      try {
        const st = G.migrate(JSON.parse(hotData.save));
        if (st && (st.savedAtMs || 0) >= (store.state.savedAtMs || 0)) store.state = st;
      } catch {}
    }
    try {
      window.claude?.hot?.snapshot?.(() => ({ save: G.serialize(store.state) }));
    } catch {}
    const M = manifest();
    const s = store.state;
    const critical = [M.titles.wordmark_evochi.file, M.icons.coin, M.icons.home, M.icons.heart, M.thumbs.file];
    const hab = !s.player ? 'welcome' : 'meadow';
    for (const l of Object.values(M.habitats[hab].layers)) critical.push(l);
    let done = 0;
    const all = critical.map((f) => loadImage(f).catch(() => null).then(() => setP(0.2 + (0.6 * ++done) / critical.length)));
    const pal = s.pet?.paletteId || s.onboarding?.draft?.paletteId || 'amber';
    all.push(preloadPet(s.pet?.stage || 1, pal).catch(() => null));
    await Promise.all(all);
    // catch up: a returning player's day boundaries and rest/vitality are derived on load
    // (the simulated device counts as background-synced; done without bumping the save time,
    // so a newer cloud save from another device still wins)
    if (s.pet && s.steps.connection === 'demo') store.state = G.syncSteps(s, [], store.now()).state;
    setP(1);
    const app = new App(root, store, SCREENS);
    window.__evochi = { app, store, G, Q };
    app.render(true);
    store.cloud = new CloudSave(store, (remote) => {
      store.replace(remote);
      app.toast('Restored your Evochi from your account', 'ok', 'paw');
    }, () => {
      // another account's local save on this browser: start clean for this account
      app.ui = {};
      app.route = null;
      store.wipe();
    });
    store.cloud.init();
    const splash = document.getElementById('splash');
    if (splash) {
      splash.style.opacity = '0';
      setTimeout(() => splash.remove(), 400);
    }
    // warm the rest of the art in the background
    const rest = [...Object.values(M.habitats.meadow.layers), ...Object.values(M.habitats.market.layers), ...Object.values(M.icons),
      M.village.square.day_dim, M.village.square.lamp_lit, ...Object.values(M.village.npcs).map((n) => n.expr.neutral)];
    if (M.home) rest.push(M.home.map.ruined, M.home.map.restored, M.home.garden.file, M.home.rooms.kitchen.file, M.home.rooms.apothecary.file);
    if (M.trails) rest.push(...Object.values(M.trails.scenes).map((x) => x.file));
    setTimeout(() => rest.forEach((f) => loadImage(f).catch(() => null)), 800);
  } catch (e) {
    console.error(e);
    const sp = document.getElementById('splash-msg');
    if (sp) sp.textContent = 'Could not load Evochi. Please reload the page.';
  }
}

const hot = typeof window !== 'undefined' ? window.claude?.hot : null;
if (hot && typeof hot.ready === 'function') hot.ready(boot);
else boot(hot?.data ?? {});
