// Encounters on the Lumen Trails: the battle shot (your Evochi from behind in the foreground, the wild
// one facing it), the intro cinematics on that same shot (the Sentinel's awakening is a story beat of its
// own), turn choreography with camera moves and ability effects, the prep screen and the result.
//
// The stage is one live element kept across re-renders (data-keep, see App.patchKept) and driven
// imperatively, so camera moves and effects never restart mid-way; the panel under it (log, actions,
// goal and result cards) is ordinary markup that re-renders with the state.
import * as G from '../game/state.js';
import * as Q from '../game/story.js';
import * as H from '../game/home.js';
import * as TR from '../game/trails.js';
import { ITEMS } from '../game/catalog.js';
import { html, raw, fmt, esc } from '../ui/dom.js';
import { icon, itemImg, url, manifest, battleSprite, charEntry, spriteAttr, BLANK } from '../ui/assets.js';
import { ICON } from '../ui/icons.js';
import { stageLabel } from '../core/app.js';
import { openStoryQuest, openStoryReward } from './village.js';
import { StageFX } from '../ui/fx.js';

const TM = () => manifest().trails;
const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
const pct = (x) => `${Math.round(x * 1000) / 10}%`;

// your Evochi's frame width (share of the shot's width) per stage, and how far right its face may reach
const PET_W = { 1: 0.44, 2: 0.52, 3: 0.68 };
const FACE_MAX_X = 0.38;
// lift your Evochi off the scene's mark a little, so its card below covers only its feet
const PET_LIFT = 0.075;
const INTRO = {
  rare: { ms: 2700, music: 'enc_wild_loop' },
  hollow: { ms: 3000, music: 'enc_boss_loop' },
  boss: { ms: 6300, music: 'enc_boss_loop' },
  standard: { ms: 2200, music: 'enc_wild_loop' },
};
// creatures whose sprite is dark: a hit brightens them instead of tinting them gold
const DARK = new Set(['hollow_sprout']);
// the intro card's line about the creature
const INTRO_LINES = {
  petalune: 'A gentle Evochi that nurtures life in the ruins. It seems cautious, but curious about you…',
  hollow_sprout: 'A forest Evochi tangled in Hollow growth. It flinches at every sound, but kindness still reaches it…',
  sentinel: 'A guardian of the Lumen Trails, asleep for an age. Its light is dim, but it still listens…',
};
// small icons for status chips, toasts, the log card and the floating numbers (24x24)
const SI = {
  leaf: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4.5 19.5c-.6-7.2 4.4-13.6 15.4-14.4.6 9.6-5.4 15.6-13 14.6" fill="#7CC456" stroke="#3F8A35" stroke-width="1.6" stroke-linejoin="round"/><path d="M5 19.5c3.4-4.6 6.6-7.6 11-10" fill="none" stroke="#2F6B2A" stroke-width="1.5" stroke-linecap="round"/></svg>',
  spark: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.5l2.3 7.2 7.2 2.3-7.2 2.3L12 21.5l-2.3-7.2L2.5 12l7.2-2.3z" fill="#FFD25A" stroke="#D8962A" stroke-width="1.3" stroke-linejoin="round"/></svg>',
  hollow: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.5l2.3 7.2 7.2 2.3-7.2 2.3L12 21.5l-2.3-7.2L2.5 12l7.2-2.3z" fill="#B48CFF" stroke="#6B3FB8" stroke-width="1.3" stroke-linejoin="round"/><circle cx="18.5" cy="5.5" r="1.8" fill="#D9C2FF"/></svg>',
  hollowed: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.5l2.3 7.2 7.2 2.3-7.2 2.3L12 21.5l-2.3-7.2L2.5 12l7.2-2.3z" fill="#B48CFF" stroke="#6B3FB8" stroke-width="1.3" stroke-linejoin="round"/><circle cx="18.5" cy="5.5" r="1.8" fill="#D9C2FF"/></svg>',
  sun: '<svg viewBox="0 0 24 24" aria-hidden="true"><g stroke="#E5A12F" stroke-width="2" stroke-linecap="round"><path d="M12 2.5v2.6M12 18.9v2.6M2.5 12h2.6M18.9 12h2.6M5.3 5.3l1.8 1.8M16.9 16.9l1.8 1.8M5.3 18.7l1.8-1.8M16.9 7.1l1.8-1.8"/></g><circle cx="12" cy="12" r="5" fill="#FFD25A" stroke="#E5A12F" stroke-width="1.6"/></svg>',
  bolt: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M13.5 2.5L5 13.5h6l-1.5 8 8.5-11h-6z" fill="#FFD25A" stroke="#C98A20" stroke-width="1.5" stroke-linejoin="round"/></svg>',
  trust: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 20.5s-7.5-4.6-9.4-9.3C1.2 7.7 3.4 4.1 7 4.1c2.1 0 3.6 1.2 5 3 1.4-1.8 2.9-3 5-3 3.6 0 5.8 3.6 4.4 7.1-1.9 4.7-9.4 9.3-9.4 9.3z" fill="#F58CA6" stroke="#C8577A" stroke-width="1.4"/></svg>',
  soothed: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 20.5s-7.5-4.6-9.4-9.3C1.2 7.7 3.4 4.1 7 4.1c2.1 0 3.6 1.2 5 3 1.4-1.8 2.9-3 5-3 3.6 0 5.8 3.6 4.4 7.1-1.9 4.7-9.4 9.3-9.4 9.3z" fill="#7FD9C9" stroke="#3E9F8F" stroke-width="1.4"/></svg>',
  bloom: '<svg viewBox="0 0 24 24" aria-hidden="true"><g fill="#F7A6BE" stroke="#D86E92" stroke-width="1.2"><circle cx="12" cy="6.5" r="3.6"/><circle cx="17.3" cy="10.4" r="3.6"/><circle cx="15.3" cy="16.6" r="3.6"/><circle cx="8.7" cy="16.6" r="3.6"/><circle cx="6.7" cy="10.4" r="3.6"/></g><circle cx="12" cy="12" r="2.8" fill="#FFD25A"/></svg>',
  charged: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.8l2.8 5.8 6.3.9-4.6 4.4 1.1 6.3L12 17.2 6.4 20.2l1.1-6.3L2.9 9.5l6.3-.9z" fill="#FFD25A" stroke="#D8962A" stroke-width="1.4" stroke-linejoin="round"/></svg>',
  unsteady: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 12.2c0-1.3 1.6-1.8 2.4-.8 1.2 1.6-.3 3.9-2.4 3.9-2.8 0-4.4-3.1-3.1-5.6 1.7-3.1 6.1-3.4 8.2-.8 2.6 3.2.6 8.2-3.6 8.9-4.6.8-8.5-3.2-7.7-7.8" fill="none" stroke="#9B5FE0" stroke-width="2.2" stroke-linecap="round"/></svg>',
  flicker: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M13 2.5L7 13h4.5L10 21.5 17 10.5h-4.5z" fill="#C9A2FF" stroke="#7A4CC8" stroke-width="1.4" stroke-linejoin="round"/></svg>',
  waking: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M2.5 12s3.6-6 9.5-6 9.5 6 9.5 6-3.6 6-9.5 6-9.5-6-9.5-6z" fill="#EADCFF" stroke="#7A4CC8" stroke-width="1.6"/><circle cx="12" cy="12" r="3.2" fill="#9B5FE0"/></svg>',
  wary: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.8l7.5 3v5.6c0 4.8-3.2 8.3-7.5 9.8-4.3-1.5-7.5-5-7.5-9.8V5.8z" fill="#8EC2F0" stroke="#3F7FC0" stroke-width="1.5" stroke-linejoin="round"/></svg>',
  tired: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3.5v12M6.5 10.5L12 16l5.5-5.5" fill="none" stroke="#E2574C" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/><path d="M5 20h14" stroke="#E2574C" stroke-width="2.2" stroke-linecap="round"/></svg>',
  target: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9" fill="#FFF" stroke="#E2574C" stroke-width="2"/><circle cx="12" cy="12" r="5.5" fill="#FBD3CF" stroke="#E2574C" stroke-width="2"/><circle cx="12" cy="12" r="2" fill="#E2574C"/></svg>',
};
const ANN_IC = { good: SI.spark, love: SI.trust, wary: SI.wary, hollow: SI.hollow, calm: SI.leaf, meh: SI.tired };
const PLACE_INFO = {
  ruins: { name: 'Mossy Ruins', line: 'A quiet grove with ancient light.', badge: 'aff_nature' },
  gate: { name: 'The Old Gate', line: 'The broken gate past the bridge.', badge: 'moon' },
};
const RARITY = { rare: 'Rare', uncommon: 'Uncommon', legendary: 'Legendary', common: 'Common' };
const RUNNER = '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="14.5" cy="4.2" r="2.2" fill="currentColor"/><path d="M10.2 8.6l3.6-1.1c.7-.2 1.4.1 1.8.7l1.6 2.6 2.6.9M12.6 8.1l-1.7 5 3.2 2.4-.9 5.1M10.9 13.1l-2.4 3.6-3.6.6M9.6 9.4L6.8 11" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>';

// ------------------------------------------------------------------ the shot
/** Where everything sits on the battle shot, in percent of the backdrop (so it lines up at any size). */
function shotGeometry(v, pet) {
  const B = TM().battle[v.scene];
  const W = B.w;
  const Hh = B.h;
  const A = B.anchors;
  const C = v.creature;
  const CB = TM().battleCreatures[C.id];
  // the wild one: its design height from the scene's perspective, capped in width
  const cg = CB.anchors.ground;
  const ct = CB.anchors.top;
  let s = (A.wild[1] - A.wild_top[1]) / (cg[1] - ct[1]);
  s = Math.min(s, ((C.size === 'large' ? 0.8 : 0.4) * W) / CB.w);
  const wl = A.wild[0] - cg[0] * s;
  const wt = A.wild[1] - cg[1] * s;
  const local = (p) => [(p[0] / CB.w) * 100, (p[1] / CB.h) * 100];
  const abs = (p) => [((wl + p[0] * s) / W) * 100, ((wt + p[1] * s) / Hh) * 100];
  const wild = {
    left: (wl / W) * 100, top: (wt / Hh) * 100, width: ((CB.w * s) / W) * 100, ar: CB.w / CB.h,
    cx: (A.wild[0] / W) * 100, cy: ((A.wild[1] - (cg[1] - ct[1]) * s * 0.55) / Hh) * 100,
    face: CB.anchors.face ? abs(CB.anchors.face) : null,
    eyes: CB.anchors.eye_l ? [local(CB.anchors.eye_l), local(CB.anchors.eye_r)] : null,
    eyesAbs: CB.anchors.eye_l ? [abs(CB.anchors.eye_l), abs(CB.anchors.eye_r)] : null,
    headY: ((wt + ct[1] * s) / Hh) * 100,
    bottom: (A.wild[1] / Hh) * 100,
    gy: (cg[1] / CB.h) * 100,
  };
  // your Evochi: a set width per stage, feet on the scene's mark, its face kept left of the wild one
  const P = charEntry(pet.stage).battle;
  const pg = P.anchors.ground;
  const pf = P.anchors.face;
  const ps = ((PET_W[pet.stage] || 0.5) * W) / P.w;
  const gx = Math.min(A.pet[0] - 0.035 * W, FACE_MAX_X * W - (pf[0] - pg[0]) * ps);
  const gy = A.pet[1] - PET_LIFT * Hh;
  const pl = gx - pg[0] * ps;
  const pt = gy - pg[1] * ps;
  const head = P.anchors.head_top || P.anchors.body_top;
  const petG = {
    left: (pl / W) * 100, top: (pt / Hh) * 100, width: ((P.w * ps) / W) * 100, ar: P.w / P.h,
    cx: ((pl + P.anchors.back[0] * ps) / W) * 100, cy: ((pt + P.anchors.back[1] * ps) / Hh) * 100,
    face: [((pl + pf[0] * ps) / W) * 100, ((pt + pf[1] * ps) / Hh) * 100],
    head: [((pl + head[0] * ps) / W) * 100, ((pt + head[1] * ps) / Hh) * 100],
    feetY: (gy / Hh) * 100,
    gy: (pg[1] / P.h) * 100,
    headLocal: [(head[0] / P.w) * 100, (head[1] / P.h) * 100],
  };
  return { B, CB, ar: W / Hh, wild, pet: petG };
}

function wildSrc(cid, st) {
  const c = TM().battleCreatures[cid];
  return url(c.states[st] || Object.values(c.states)[0]);
}

function petExpr(v) {
  if (v.done === 'success') return 'excited';
  if (v.energy < 25) return 'sleepy';
  return 'default';
}

function meterHTML(cls, label, frac, val, inside = true) {
  return html`<div class="np-meter ${cls}">${inside ? '' : html`<span class="np-lbl">${label}</span>`}<div class="np-bar"><i style="width:${pct(clamp(frac, 0, 1))}"></i>${inside ? html`<span>${label}</span>` : ''}</div><b class="np-val">${val}</b></div>`;
}

function stageHTML(ctx, v, g) {
  const C = v.creature;
  const pet = ctx.state.pet;
  const u = ctx.ui('encounter');
  const start = v.intro === 'boss' && u.phase === 'intro' ? 'dormant' : v.stateKey;
  const hollowTheme = C.kind === 'hollow';
  const A = TR.AFFINITIES[C.affinity];
  const dust = Array.from({ length: 14 }, (_, i) => html`<i style="--i:${i};--x:${(i * 37) % 100}%"></i>`);
  return html`<div class="enc-stage" data-keep="stage:${v.seed}" data-shot="wide" style="--wx:${pct(g.wild.cx / 100)};--wy:${pct(g.wild.cy / 100)};--px:${pct(g.pet.cx / 100)};--py:${pct(g.pet.cy / 100)};--fx:${pct((g.wild.face?.[0] ?? g.wild.cx) / 100)};--fy:${pct((g.wild.face?.[1] ?? g.wild.cy) / 100)};--hs:${C.size === 'large' ? 1 : 1.18};--hk:${C.size === 'large' ? 0 : 1}" data-tone="${DARK.has(C.id) ? 'dark' : 'light'}">
    <div class="enc-view">
      <div class="enc-world" style="--ar:${g.ar}"><div class="enc-cam"><div class="enc-shake"><div class="enc-punch"><div class="enc-drift">
        <img class="enc-bg" src="${url(g.B.file)}" alt="">
        <div class="enc-aura" style="left:${pct(g.wild.cx / 100)};top:${pct(g.wild.cy / 100)}"></div>
        <canvas class="enc-fxb" aria-hidden="true"></canvas>
        <div class="enc-wild" style="left:${pct(g.wild.left / 100)};top:${pct(g.wild.top / 100)};width:${pct(g.wild.width / 100)};--gy:${pct(g.wild.gy / 100)}">
          <i class="enc-shadow"></i>
          <div class="w-body"><img class="w-img" src="${wildSrc(C.id, start)}" alt="${C.name}" style="aspect-ratio:${g.wild.ar}">
            ${g.wild.eyes ? html`<span class="w-eyes" aria-hidden="true">${g.wild.eyes.map((e) => html`<i style="left:${pct(e[0] / 100)};top:${pct(e[1] / 100)}"></i>`)}</span>` : ''}</div>
        </div>
        ${pet ? html`<div class="enc-pet" style="left:${pct(g.pet.left / 100)};top:${pct(g.pet.top / 100)};width:${pct(g.pet.width / 100)};--gy:${pct(g.pet.gy / 100)};--hx:${pct(g.pet.headLocal[0] / 100)};--hy:${pct(g.pet.headLocal[1] / 100)}">
          <i class="enc-shadow"></i>
          <div class="p-body"><img class="p-img" src="${BLANK}" alt="${pet.name}" style="aspect-ratio:${g.pet.ar}"></div>
          <span class="p-bang" aria-hidden="true">!</span>
        </div>` : ''}
        <img class="enc-fg" src="${url(g.B.fg)}" alt="">
        <canvas class="enc-fxc" aria-hidden="true"></canvas>
        <div class="enc-vfx" aria-hidden="true"></div>
      </div></div></div></div></div>
      <div class="enc-grade" aria-hidden="true"></div>
      <div class="enc-flash" aria-hidden="true"></div>
      <div class="enc-dust" aria-hidden="true">${dust}</div>
      <section class="enc-plate wild-plate ${hollowTheme ? 'hollow' : ''}" aria-label="${C.name}">
        <span class="np-face ${hollowTheme ? 'hollow' : ''}"><img src="${icon('creature_' + C.id)}" alt=""></span>
        <div class="np-id"><b class="np-name">${C.name}</b><span class="np-row"><span class="np-kind">${v.meterLabel}</span><b class="np-val">${Math.round(v.meter)} / ${v.max}</b></span></div>
        <span class="np-aff ${hollowTheme ? 'faded' : ''}"><img src="${icon(A.icon)}" alt="${A.name}"></span>
        <div class="np-bar thin ${v.goal === 'befriend' ? 'calm' : 'inst'}"><i style="width:${pct(clamp(v.meter / v.max, 0, 1))}"></i></div>
        <div class="enc-under"><span class="enc-goalpill"><span class="gi">${raw(SI.target)}</span><b>${v.goal === 'befriend' ? 'Earn its trust' : 'Restore its light'}</b><span class="tn">Turn ${v.turn + 1}</span></span><span class="chips"></span></div>
        <div class="enc-ann" aria-live="polite"></div>
      </section>
      ${pet ? html`<section class="enc-plate pet-plate" aria-label="${pet.name}">
        <span class="np-face pet"><img data-sprite="${spriteAttr(pet.stage, pet.paletteId, 'happy', Object.values(pet.equipped || {}), '', 90)}" src="${BLANK}" alt=""></span>
        <div class="np-id"><b class="np-name">${pet.name}</b><span class="np-lv">Lv. ${ctx.d.pet.level}</span></div>
        ${meterHTML('energy', 'Energy', v.energy / v.energyMax, `${v.energy} / ${v.energyMax}`, false)}
        <div class="pet-chips"></div>
      </section>` : ''}
      <div class="enc-toast" aria-live="polite"></div>
    </div>
    <div class="enc-bars" aria-hidden="true"><i></i><i></i></div>
    <button class="enc-skip" data-act="skip-intro" data-k="skip-intro">Skip ›</button>
  </div>`;
}

// ------------------------------------------------------------------ stage helpers (imperative)
const stageEl = (root) => root?.querySelector?.('.enc-stage') || document.querySelector('.enc-stage');

function later(u, ms, fn) {
  ms *= globalThis.__evochiSlow || 1; // slow motion for capturing frames (playtest tooling only)
  const t = setTimeout(() => {
    u.timers = (u.timers || []).filter((x) => x !== t);
    fn();
  }, ms);
  (u.timers = u.timers || []).push(t);
  return t;
}

function clearTimers(u) {
  for (const t of u.timers || []) clearTimeout(t);
  u.timers = [];
}

/** Move the camera to a shot: eased (the default), as a cut, or 'fast' for the beats of a turn. */
function shot(st, name, instant = false, speed = '') {
  if (!st) return;
  if (instant) {
    st.classList.add('cut');
    st.dataset.shot = name;
    void st.offsetWidth;
    st.classList.remove('cut');
  } else st.dataset.shot = name;
  if (speed) st.dataset.speed = speed;
  else delete st.dataset.speed;
}

// the canvas effects live on the stage element, so they survive re-renders with it
const fxOf = (st) => st?.__fx || null;
function ensureFX(ctx, st) {
  if (!st) return null;
  if (st.__fx) return st.__fx;
  if (ctx.app.reducedMotion) return null;
  const world = st.querySelector('.enc-world');
  const back = st.querySelector('.enc-fxb');
  const front = st.querySelector('.enc-fxc');
  if (!world || !back || !front) return null;
  st.__fx = new StageFX(world, back, front);
  st.__fx.start();
  return st.__fx;
}

/** The hit-stop: for a few frames everything on the shot holds still, then carries on. */
function hitstop(st, ms) {
  if (!st || !ms) return;
  st.classList.add('hitstop');
  const anims = st.querySelector('.enc-world')?.getAnimations?.({ subtree: true }) || [];
  const running = anims.filter((a) => a.playState === 'running');
  for (const a of running) {
    try { a.pause(); } catch { /* fine */ }
  }
  fxOf(st)?.freeze(ms);
  setTimeout(() => {
    st.classList.remove('hitstop');
    for (const a of running) {
      try { a.play(); } catch { /* fine */ }
    }
  }, ms);
}

/** The camera jolts in toward the wild one (or your Evochi) and eases back. */
function punch(st, at = 'wild', big = false) {
  const el = st?.querySelector('.enc-punch');
  if (!el) return;
  el.dataset.at = at;
  el.classList.remove('on', 'big');
  void el.offsetWidth;
  el.classList.add('on');
  if (big) el.classList.add('big');
  setTimeout(() => el.classList.remove('on', 'big'), big ? 720 : 520);
}

const easeOut3 = (t) => 1 - (1 - t) ** 3;
/** A value eased over ms on the animation clock (so recordings stay frame-exact). */
function tween(ms, fn, ease = easeOut3) {
  const t0 = performance.now();
  const step = (now) => {
    const k = Math.min(1, (now - t0) / Math.max(1, ms));
    fn(ease(k));
    if (k < 1) requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}

/** Between turns your Evochi blinks and the wild one glances about, so the shot is never dead still. */
function scheduleIdle(ctx) {
  const u = ctx.ui('encounter');
  u.idleTimer = setTimeout(() => {
    const st = stageEl();
    const v = ctx.d.trails?.encounter;
    if (!st || !v || !st.isConnected || ctx.app.route.id !== 'encounter') {
      u.idleOn = false;
      return;
    }
    const quiet = !u.busy && !u.holdPet && (u.phase === 'play' || u.phase === 'card');
    if (quiet && petExpr(v) === 'default') {
      setPet(ctx, st, 'blink');
      setTimeout(() => {
        if (!u.busy && !u.holdPet) setPet(ctx, st, petExpr(v));
      }, 150);
    }
    if (quiet && !v.done && Math.random() < 0.55) retrigger(st.querySelector('.enc-wild'), 'look', 1500);
    scheduleIdle(ctx);
  }, 2400 + Math.random() * 2600);
}

function retrigger(el, cls, ms) {
  if (!el) return;
  el.classList.remove(cls);
  void el.offsetWidth;
  el.classList.add(cls);
  if (ms) setTimeout(() => el.classList.remove(cls), ms);
}

function shake(st, big = false, rm = false) {
  if (rm) return;
  retrigger(st?.querySelector('.enc-shake'), big ? 'shake-l' : 'shake-s', big ? 900 : 450);
}

function flash(st, kind = 'white') {
  const f = st?.querySelector('.enc-flash');
  if (!f) return;
  f.dataset.kind = kind;
  retrigger(f, 'on', 600);
}

function vfx(st, cls, x, y, inner = '', life = 1400, style = '') {
  const layer = st?.querySelector('.enc-vfx');
  if (!layer) return null;
  const el = document.createElement('div');
  el.className = 'fx ' + cls;
  el.style.cssText = `left:${x}%;top:${y}%;${style}`;
  el.innerHTML = inner;
  layer.appendChild(el);
  setTimeout(() => el.remove(), life);
  return el;
}

function floatText(st, x, y, text, kind) {
  const ic = /Calm/.test(text) ? SI.leaf : /Instab/.test(text) ? SI.hollow : /Energy/.test(text) ? SI.bolt : '';
  // the icon names the meter, so the long word can go: "−21 ✦" rather than "−21 Instability"
  const t = text.replace(/ Instability$/, '');
  vfx(st, 'float ' + kind, x, y, `<span class="fi">${ic}</span><span>${esc(t)}</span>`, 1500);
}

/** Something travels from a to b (percent of the shot) along an arc; returns its flight time. */
function projectile(st, cls, a, b, inner, ms, arc = 0) {
  const el = vfx(st, 'proj ' + cls, 0, 0, `<span class="pv" style="left:${a[0]}%;top:${a[1]}%">${inner}</span>`, ms + 80,
    `--dx:${b[0] - a[0]};--dy:${b[1] - a[1]};--arc:${arc};--t:${ms}ms`);
  return el;
}

function setMeter(plate, frac, val) {
  if (!plate) return;
  const bar = plate.querySelector('.np-bar > i');
  if (bar) bar.style.width = pct(clamp(frac, 0, 1));
  const t = plate.querySelector('.np-val');
  if (t) t.textContent = val;
}

function setWild(st, cid, state) {
  const img = st?.querySelector('.w-img');
  if (!img || img.dataset.state === state) return;
  img.dataset.state = state;
  img.src = wildSrc(cid, state);
}

function setPet(ctx, st, expr) {
  const pet = ctx.state.pet;
  const img = st?.querySelector('.p-img');
  if (!pet || !img) return;
  const ov = Object.values(pet.equipped || {});
  const key = [pet.stage, pet.paletteId, expr, ov.join('+')].join('|');
  if (img.dataset.key === key) return;
  img.dataset.key = key;
  battleSprite(pet.stage, pet.paletteId, expr, ov).then((src) => {
    if (img.dataset.key === key) img.src = src;
  });
}

/** Bring the live stage in line with the state (or with the mid-turn numbers while a turn plays out). */
function syncStage(ctx, st, v) {
  if (!st || !v) return;
  const u = ctx.ui('encounter');
  const d = u.disp || {};
  const meter = d.meter ?? v.meter;
  const energy = d.energy ?? v.energy;
  setMeter(st.querySelector('.wild-plate'), meter / v.max, `${Math.round(meter)} / ${v.max}`);
  setMeter(st.querySelector('.pet-plate'), energy / v.energyMax, `${Math.round(energy)} / ${v.energyMax}`);
  if (!u.holdWild) setWild(st, v.creature.id, v.stateKey);
  if (!u.holdPet) setPet(ctx, st, petExpr(v));
  const w = st.querySelector('.enc-wild');
  if (w && !u.busy) w.dataset.mood = v.done ? 'done' : v.mood || '';
  st.classList.toggle('phase2', !!v.phase2);
  st.classList.toggle('hollow', v.creature.kind === 'hollow' && v.done !== 'success');
  syncStatus(ctx, st, v);
  // the air: motes over the grove, Hollow embers around the wild one
  const fx = fxOf(st);
  const g = u.geom;
  if (fx && g) {
    const kind = v.done === 'success' ? 'won' : v.creature.kind === 'hollow' ? 'hollow' : 'gold';
    if (st.dataset.amb !== kind) {
      st.dataset.amb = kind;
      fx.setAmbient(kind, kind === 'hollow'
        ? { x: g.wild.cx - 14, y: g.wild.headY - 4, w: 28, h: g.wild.bottom - g.wild.headY + 4 }
        : { x: 4, y: 10, w: 92, h: 62 });
    }
  }
}

// ------------------------------------------------------------------ intros (on the same shot)
// The intro ends on the hero shot of the wild one with the big title, the goal and Begin Encounter
// (the 'card' phase); your Evochi steps in when you begin.
function playIntro(ctx, st, v) {
  const u = ctx.ui('encounter');
  const rm = ctx.app.reducedMotion;
  const I = INTRO[v.intro] || INTRO.standard;
  const C = v.creature;
  ctx.app.root.classList.add('cinematic');
  const done = () => {
    ctx.app.root.classList.remove('cinematic');
    if (u.phase !== 'intro') return;
    u.phase = 'card';
    u.holdWild = false;
    u.holdPet = false;
    ctx.rerender();
  };
  if (rm) {
    shot(st, 'hero', true);
    st.classList.add('lit', 'eye-l', 'eye-r');
    if (v.intro === 'boss') setWild(st, C.id, v.stateKey);
    ctx.music(I.music);
    later(u, 900, done);
    return;
  }
  st.classList.add('intro-' + v.intro);
  const fx = ensureFX(ctx, st);
  const g = u.geom;
  const W = [g.wild.cx, g.wild.cy];
  if (v.intro === 'boss') {
    // the Sentinel's awakening: dark and still, a rumble, stones falling, its eyes light one after the
    // other, the gate shakes and crackles, your Evochi flinches, and the music turns
    u.holdWild = true;
    u.holdPet = true;
    setWild(st, C.id, 'dormant');
    setPet(ctx, st, 'default');
    shot(st, 'face', true);
    ctx.music('none');
    later(u, 300, () => {
      ctx.sfx('enc_rumble', 0.9);
      st.classList.add('trembling');
      shake(st, false);
      fx?.burst([W[0], g.wild.headY - 6], 6, { shape: 'rock', pal: 'rock', blend: 'source-over', speed: 6, vary: 0.6, angle: Math.PI / 2, spread: 0.5, size: 1.6, sizeK: 'hold', alphaK: 'hold', life: 1.1, gravity: 120, spin: 5, jitter: 12 });
    });
    later(u, 1100, () => shake(st, false));
    later(u, 1500, () => {
      ctx.sfx('enc_awaken', 0.9);
      st.classList.add('eye-l');
      if (g.wild.eyesAbs) fx?.flashAt(g.wild.eyesAbs[0], { size: 14, life: 1.2, pal: 'violet', alphaK: 'inout', sizeK: 'grow' });
    });
    later(u, 2300, () => {
      st.classList.add('eye-r');
      if (g.wild.eyesAbs) fx?.flashAt(g.wild.eyesAbs[1], { size: 14, life: 1.2, pal: 'violet', alphaK: 'inout', sizeK: 'grow' });
    });
    later(u, 3300, () => {
      setWild(st, C.id, 'hollow');
      st.classList.add('lit');
      fx?.embers(W, 18, { pal: 'violet', w: 26, h: 24, life: 1.6 });
      fx?.crackleAround(W, { r: 16, n: 4, ms: 500 });
    });
    later(u, 3850, () => {
      shake(st, true);
      flash(st, 'violet');
      punch(st, 'wild', true);
      fx?.ring(W, { r0: 4, r1: 48, ms: 800, pal: 'violet', width: 3 });
      fx?.hollowShards(W, 14, 1.3);
      fx?.dustBurst([W[0], g.wild.bottom - 2], 12, 1.2);
      fx?.crackleAround(W, { r: 22, n: 6, ms: 700 });
      fx?.pulse({ pal: 'dark', ms: 900, alpha: 0.6 });
      shot(st, 'wide');
      st.classList.add('pet-in');
    });
    later(u, 4500, () => {
      setPet(ctx, st, 'surprised');
      retrigger(st.querySelector('.enc-pet'), 'flinch', 1100);
      ctx.sfx('pet_chirp', 0.5);
      ctx.music(I.music);
    });
    later(u, 5500, () => {
      st.classList.remove('trembling');
      shot(st, 'hero');
    });
    later(u, I.ms, () => {
      u.holdPet = false;
      setPet(ctx, st, 'determined');
      done();
    });
    return;
  }
  // rare / hollow / standard: close on the wild one, a reaction, then the hero shot for the title
  shot(st, 'close', true);
  ctx.music(I.music);
  if (v.intro === 'hollow') {
    st.classList.add('silhouette');
    later(u, 500, () => {
      ctx.sfx('enc_surge', 0.6);
      fx?.ring(W, { r0: 3, r1: 40, ms: 800, pal: 'violet', width: 2.6 });
      fx?.embers(W, 20, { pal: 'violet', w: 22, h: 20, life: 1.6 });
      fx?.crackleAround(W, { r: 14, n: 4, ms: 600 });
      fx?.smoke([W[0], g.wild.bottom], 6, { scale: 1.1 });
      fx?.pulse({ pal: 'dark', ms: 900, alpha: 0.45 });
      shake(st, false);
    });
    later(u, 1500, () => st.classList.remove('silhouette'));
  } else {
    later(u, 900, () => {
      retrigger(st.querySelector('.enc-wild'), 'bang', 0);
      ctx.sfx('pet_chirp', 0.45);
      fx?.burst([W[0], g.wild.headY], 8, { shape: 'sparkle', pal: 'gold', speed: 30, vary: 0.5, drag: 2.5, size: 3, sizeK: 'spark', life: 0.8, spin: 3, gravity: 10 });
    });
  }
  later(u, v.intro === 'hollow' ? 1800 : 1500, () => shot(st, 'hero'));
  later(u, I.ms, done);
}

function skipIntro(ctx) {
  const u = ctx.ui('encounter');
  ctx.app.root.classList.remove('cinematic');
  const st = stageEl();
  const v = ctx.d.trails?.encounter;
  clearTimers(u);
  if (st && v) {
    st.classList.remove('trembling', 'silhouette');
    st.classList.add('lit', 'eye-l', 'eye-r');
    if (v.intro === 'boss') setWild(st, v.creature.id, v.stateKey);
    shot(st, 'hero', true);
    ctx.music((INTRO[v.intro] || INTRO.standard).music);
  }
  u.holdWild = false;
  u.holdPet = false;
  u.phase = 'card';
  ctx.rerender();
}

// ------------------------------------------------------------------ words (the board's feedback language)
const theName = (C) => (C.id === 'sentinel' ? 'The Sentinel' : C.id === 'hollow_sprout' ? 'The Sprout' : C.name);

/** Your line for the log card and the announcement it may make: title, flavour, toast. */
function youLine(ctx, v, A, itemId) {
  const C = v.creature;
  const pet = ctx.state.pet?.name || 'Your Evochi';
  const hollow = C.kind === 'hollow';
  if (A.kind === 'item') {
    const it = ITEMS[itemId];
    const f = TR.itemEffect(itemId, v.goal, C.id);
    const liked = !!f?.liked;
    const weak = !liked && (f?.amount || 0) < 10;
    return { title: `${pet} offers ${it?.name || 'a gift'}!`, sub: liked ? `${C.name} loves it!` : weak ? 'It’s not very effective…' : `${C.name} sniffs it curiously…`,
      ann: liked ? { text: `${theName(C)} loves it!`, tone: 'love' } : weak ? { text: 'It’s not very effective…', tone: 'meh' } : null };
  }
  if (A.kind === 'companion') return { title: 'Petalune uses Petal Hush!', sub: 'A soft, green hum fills the air…', ann: null };
  if (A.kind === 'light') return { title: `${pet} uses Lumen Glow!`, sub: hollow ? 'Warm light pushes back the Hollow…' : `A warm light soothes ${C.name}…`,
    ann: hollow ? { text: 'It’s very effective!', tone: 'good' } : null };
  if (A.kind === 'physical') {
    const fun = v.goal === 'befriend' && v.curious;
    return { title: `${pet} uses Gentle Nudge!`, sub: fun ? 'It’s having fun!' : 'The air settles a little…', ann: fun ? { text: 'It’s having fun!', tone: 'good' } : null };
  }
  return { title: `${pet} uses Soothe!`, sub: `${pet} rests. Energy returns.`, ann: null };
}

/** The wild one's reply: a short headline (and whether it is worth a toast) over the game's own line. */
function wildLine(v, ev, text) {
  const C = v.creature;
  const m = ev.mood;
  const the = theName(C);
  if (v.goal === 'befriend') {
    if (ev.kind === 'item' && m === 'curious' && ev.wild > 0) return { title: 'Trust is growing.', sub: text, tone: 'love', ann: true };
    if (m === 'wary') return { title: `${C.name} seems wary.`, sub: text, tone: 'wary', ann: true };
    if (m === 'calm') return { title: `${C.name} looks more at ease!`, sub: text, tone: 'love', ann: true };
    return { title: `${C.name} is watching you closely…`, sub: text, tone: 'calm', ann: false };
  }
  if (m === 'waking') return { title: `${the} stirs!`, sub: text, tone: 'hollow', ann: true };
  if (m === 'surging' && ev.drain) return { title: 'Hollow energy lashes out!', sub: text, tone: 'hollow', ann: true };
  if (m === 'surging') return { title: 'Hollow energy surged!', sub: text, tone: 'hollow', ann: true };
  if (m === 'flickering') return { title: `${the}’s light flickers…`, sub: text, tone: 'calm', ann: false };
  return { title: `${the} is calming down…`, sub: text, tone: 'calm', ann: true };
}

/** What the log card shows when nothing is playing: the last turn's lines, or how it began. */
function currentLog(ctx, v, u) {
  if (u.log && u.log.seed === v.seed) return u.log;
  const C = v.creature;
  if (v.done === 'success') return finalLog(v);
  if (!v.turn) {
    if (v.goal === 'befriend') return { title: `A wild ${C.name} appeared!`, sub: 'It watches you from a distance…', who: 'wild' };
    return { title: C.boss ? 'The Sentinel is awake!' : 'Hollow energy shudders through the ruins…', sub: v.log[0]?.text || '', who: 'wild' };
  }
  return { title: v.log[v.log.length - 1]?.text || '', sub: '', who: v.log[v.log.length - 1]?.who || 'wild' };
}

function finalLog(v) {
  const C = v.creature;
  return v.goal === 'befriend' ? { title: `${C.name} trusts you.`, sub: 'A new friend may join you soon…', who: 'wild' }
    : { title: `${C.name} restored.`, sub: 'The Hollow energy fades, and its light returns.', who: 'wild' };
}

// ------------------------------------------------------------------ a turn, choreographed
// Every move has the same four beats: a wind-up, the action, the impact (a hit-stop, a soft flash on
// the one that was hit, a camera punch, the effect from the board's library at the point of contact)
// and the recovery, with the number popping first and the meter following it. The colours keep one
// language: gold light and green leaves are you, violet crystals and crackle are the Hollow.
function runTurn(ctx, actionId, itemId) {
  const u = ctx.ui('encounter');
  if (u.busy) return;
  const before = ctx.d.trails.encounter;
  const r = ctx.act(TR.encounterAct, actionId, itemId);
  if (r.error) return;
  const after = TR.encounterView(ctx.store.state, ctx.now);
  const ev = r.events.find((e) => e.type === 'encounter_turn') || { you: 0, wild: 0 };
  const A = TR.ACTIONS[actionId];
  const st = stageEl();
  const g = u.geom;
  const rm = ctx.app.reducedMotion;
  const k = rm ? 0.35 : 1;
  const sign = before.goal === 'befriend' ? 1 : -1;
  const label = before.meterLabel;
  const mid = clamp(before.meter + sign * (ev.you || 0), 0, before.max);
  const cost = Math.max(0, A.energy);
  const hollow = before.creature.kind === 'hollow';
  u.busy = true;
  u.holdPet = true;
  u.holdWild = true;
  u.disp = { meter: before.meter, energy: before.energy - cost };
  // the panel: lock the buttons, show your line
  const panel = document.querySelector('.enc-panel');
  panel?.classList.add('busy');
  panel?.querySelectorAll('button').forEach((b) => (b.disabled = true));
  const wildText = after.log[after.log.length - 1]?.text || '';
  const yl = youLine(ctx, before, A, itemId);
  setLog(ctx, yl.title, yl.sub, 'you');
  syncStage(ctx, st, before);
  setPet(ctx, st, 'determined');
  const fx = ensureFX(ctx, st);
  const W = [g.wild.cx, g.wild.cy];                       // the wild one's body
  const WF = g.wild.face || [W[0], g.wild.headY + 6];      // its face
  const WC = [W[0] - g.wild.width * 0.28, W[1] + 3];       // its near side, where a nudge lands
  const WG = [W[0] - 3, g.wild.bottom];                    // the ground at its feet
  const P = g.pet.head;                                    // your Evochi's head
  const PC = [g.pet.cx, g.pet.cy];                         // its body
  const PG = [g.pet.cx, g.pet.feetY];                      // the ground at its feet
  const petBody = st?.querySelector('.enc-pet');
  const wildBody = st?.querySelector('.enc-wild');
  // the numbers pop beside its head (the board's "+16 Calm" bubble), clear of the toasts on the left
  const numX = W[0] + g.wild.width * 0.3;
  const numY = before.creature.size === 'large' ? WF[1] - 4 : Math.max(g.wild.headY + 4, W[1] - 8);
  const meterTo = (to, ms) => {
    const from = u.disp?.meter ?? before.meter;
    tween(ms * k, (t) => {
      if (!u.disp) return;
      u.disp.meter = from + (to - from) * t;
      syncStage(ctx, st, before);
    });
  };
  const energyTo = (to, ms) => {
    const from = u.disp?.energy ?? before.energy;
    tween(ms * k, (t) => {
      if (!u.disp) return;
      u.disp.energy = from + (to - from) * t;
      syncStage(ctx, st, before);
    });
  };
  // the bouncy hit feedback: stars that pop out and fall
  const stars = (p, n = 8, s = 1) => fx?.burst(p, n, { shape: 'star', pal: 'gold', speed: 46 * s, vary: 0.5, drag: 2.6, size: 3.2 * s, sizeK: 'pop', alphaK: 'hold', life: 0.75, spin: 7, gravity: 70 });
  let impact = 900;
  let replyGap = 800;
  // 1-2. your move
  if (A.kind === 'light') {
    // Lumen Glow: motes gather into your Evochi as it brightens, then a comet of gold light flies
    shot(st, 'pet', false, 'fast');
    retrigger(petBody, 'cast', 720);
    ctx.sfx('enc_glow', 0.7);
    fx?.converge(P, 24, { r: 19, pal: 'gold', life: 0.44 * k, size: 2.6 });
    fx?.halo(P, { size: 26, life: 0.5, pal: 'gold', layer: 'front', alpha: 0.9 });
    later(u, 440 * k, () => {
      shot(st, 'wild', false, 'fast');
      fx?.flashAt(P, { size: 30, life: 0.28, pal: 'gold' });
      if (fx) fx.comet(P, WF, { ms: 210 * k, pal: 'gold', size: 7.5, bow: -9, trail: 4, onArrive: () => landed() });
      else later(u, 230 * k, () => landed());
    });
    impact = 680 * k;
  } else if (A.kind === 'physical') {
    // Gentle Nudge: a crouch and a hop into it, Lumen Wisps winding along, a Dust Burst where it lands
    shot(st, 'pet', false, 'fast');
    retrigger(petBody, 'lunge', 900);
    ctx.sfx('enc_whoosh', 0.6);
    later(u, 110 * k, () => fx?.wisps(PC, WC, { n: 5, ms: 300 * k }));
    later(u, 190 * k, () => {
      shot(st, 'wild', false, 'fast');
      fx?.dust(PG, 5, { scale: 0.8 });
    });
    impact = 320 * k;
  } else if (A.kind === 'restore') {
    // Soothe: it settles, Healing Sparkles and leaves rise, rings of calm spread, Energy counts up
    shot(st, 'pet', false, 'fast');
    retrigger(petBody, 'rest', 1300);
    setPet(ctx, st, 'sleepy');
    ctx.sfx('enc_soothe', 0.6);
    fx?.halo(P, { size: 54, life: 1.3, pal: 'teal', layer: 'front', alpha: 0.5 });
    for (let i = 0; i < 3; i++) later(u, (120 + i * 230) * k, () => fx?.ring(P, { r0: 4, r1: 40, ms: 1000, pal: 'teal', width: 1.6, alpha: 0.7 }));
    fx?.healing([P[0], P[1] + 4], { n: 18, w: 30, h: 22 });
    later(u, 450 * k, () => fx?.healing([P[0], P[1] + 2], { n: 9, w: 26, h: 16 }));
    later(u, 650 * k, () => {
      floatText(st, P[0], P[1] + 2, '+30 Energy', 'energy');
      energyTo(Math.min(before.energyMax, before.energy + 30), 520);
    });
    later(u, 950 * k, () => shot(st, 'wide'));
    impact = 1150 * k;
    replyGap = 650;
  } else if (A.kind === 'item') {
    // an item: it turns over in an arc with a sparkle behind it
    shot(st, 'pet', false, 'fast');
    retrigger(petBody, 'toss', 600);
    ctx.sfx('enc_whoosh', 0.5);
    const im = new Image();
    if (itemId) im.src = itemImg(itemId);
    later(u, 230 * k, () => {
      shot(st, 'wild', false, 'fast');
      if (fx) fx.comet([P[0], P[1] - 2], [WF[0], WF[1] + 2], { ms: 600 * k, pal: 'gold', size: 3, bow: -24, trail: 1, ease: 'inout', img: im, imgSize: 11, spin: 9, onArrive: () => landed() });
      else {
        projectile(st, 'toss', P, [WF[0], WF[1] + 2], itemId ? `<img src="${itemImg(itemId)}" alt="">` : '', 600 * k, -20);
        later(u, 600 * k, () => landed());
      }
    });
    impact = 830 * k;
  } else if (A.kind === 'companion') {
    // Petal Hush: Petalune swoops in and a stream of Flower Petals winds across to the wild one
    shot(st, 'wide');
    vfx(st, 'buddy', 14, 46, `<img src="${icon('creature_petalune')}" alt="">`, 1900);
    ctx.sfx('enc_soothe', 0.6);
    later(u, 260 * k, () => fx?.stream([10, 42], WF, 48, { pal: 'pink', ms: 650 * k, size: 4 }));
    later(u, 380 * k, () => fx?.wisps([12, 44], WF, { n: 4, ms: 620 * k }));
    later(u, 520 * k, () => shot(st, 'wild', false, 'fast'));
    impact = 1100 * k;
    replyGap = 900;
  }
  // 3. the impact on the wild one: the visuals fire the moment the projectile lands (or on the beat for
  // the moves without one); the number and the meter follow on the beat
  let landedOnce = false;
  const landed = () => {
    if (landedOnce) return;
    landedOnce = true;
    if (A.kind === 'light') {
      // Golden Pulse winds out round the face; on a Hollow one, its crystals break off
      hitstop(st, 100 * k);
      retrigger(wildBody, 'hit', 600);
      fx?.flashAt(WF, { size: 26, life: 0.3, pal: 'gold' });
      fx?.goldenPulse(WF, { r1: 24, ms: 700 });
      stars(WF, 7, 0.9);
      if (hollow) fx?.hollowShards(WF, 12, 1);
      else fx?.shards(WF, 14, 'gold', 0.8);
      punch(st, 'wild');
      later(u, 100 * k, () => shake(st, false, rm));
      ctx.sfx('reward_chime', 0.35);
    } else if (A.kind === 'physical') {
      hitstop(st, 80 * k);
      retrigger(wildBody, 'hit', 600);
      fx?.dustBurst(WC, 8, 0.9, { ground: WG });
      stars(WC, 7, 1);
      fx?.ring(WC, { r0: 1, r1: 16, ms: 320, pal: 'white', width: 1.6, alpha: 0.8 });
      punch(st, 'wild');
      later(u, 80 * k, () => shake(st, false, rm));
      ctx.sfx('play_boing', 0.5);
    } else if (A.kind === 'item') {
      hitstop(st, 60 * k);
      retrigger(wildBody, 'munch', 800);
      fx?.burst(WF, 10, { shape: 'sparkle', pal: 'gold', speed: 38, vary: 0.5, drag: 3, size: 3.4, sizeK: 'spark', life: 0.7, spin: 3, gravity: 30 });
      fx?.flashAt(WF, { size: 18, life: 0.25, pal: 'gold' });
      fx?.ring(WF, { r0: 1, r1: 16, ms: 320, pal: 'white', width: 1.4, alpha: 0.75 });
      if (ev.you >= 20) later(u, 320 * k, () => fx?.hearts(WF, 4));
      ctx.sfx('pet_chirp', 0.45);
    } else if (A.kind === 'companion') {
      retrigger(wildBody, 'perk', 700);
      fx?.hearts(WF, 3);
      fx?.ring(WF, { r0: 3, r1: 22, ms: 600, pal: 'pink', width: 1.4, alpha: 0.7, blend: 'source-over' });
    } else if (ev.you) {
      retrigger(wildBody, 'perk', 700);
      fx?.hearts(WF, 2, { pal: 'teal' });
    }
  };
  later(u, impact, () => {
    if (A.kind !== 'light' && A.kind !== 'item') landed();
    // the number pops, then the meter follows it
    later(u, A.kind === 'restore' ? 0 : 110 * k, () => {
      landed();
      if (ev.you) floatText(st, numX, numY, `${sign > 0 ? '+' : '−'}${ev.you} ${label}`, hollow ? 'good violet' : 'good');
      meterTo(mid, 380);
      if (yl.ann) later(u, 160 * k, () => announce(st, yl.ann.text, yl.ann.tone));
    });
  });
  // 4. the reply (or the finish)
  const replyAt = impact + replyGap * k;
  if (after.done === 'success') {
    later(u, replyAt - 200 * k, () => finishChoreo(ctx, st, before, after));
    return;
  }
  later(u, replyAt, () => {
    const wl = wildLine(before, ev, wildText);
    setLog(ctx, wl.title, wl.sub, 'wild');
    if (wl.ann) announce(st, wl.title, wl.tone);
    const mood = ev.mood;
    const bad = ev.wild < 0;
    shot(st, mood === 'surging' || ev.drain ? 'wild' : 'wide');
    if (wildBody) wildBody.dataset.mood = mood || '';
    if (mood === 'wary') {
      retrigger(wildBody, 'skitter', 900);
      ctx.sfx('enc_whoosh', 0.35);
      fx?.dust(WG, 5, { scale: 0.8 });
    } else if (mood === 'curious') {
      retrigger(wildBody, 'tilt', 900);
      vfx(st, 'bubble', W[0] + 6, g.wild.headY - 2, '?', 1300);
    } else if (mood === 'calm') {
      retrigger(wildBody, 'perk', 700);
      fx?.hearts(WF, 2);
    } else if (mood === 'surging' || mood === 'waking') {
      // the Hollow swells in it: Violet Crackle, Hollow Shards, a dark pulse
      ctx.sfx('enc_surge', 0.6);
      retrigger(wildBody, 'surge', 900);
      fx?.ring(W, { r0: 4, r1: 42, ms: 700, pal: 'violet', width: 2.6 });
      fx?.crackleAround(W, { r: 16, n: mood === 'waking' ? 7 : 5, ms: 650 });
      fx?.hollowShards(W, 8, 0.8);
      fx?.embers(W, 20, { pal: 'violet', w: 26, h: 24, life: 1.5 });
      fx?.smoke(WG, 6);
      fx?.pulse({ pal: 'dark', ms: 850, alpha: mood === 'waking' ? 0.6 : 0.4 });
      later(u, 300 * k, () => shake(st, mood === 'waking', rm));
      if (mood === 'waking') {
        flash(st, 'violet');
        punch(st, 'wild', true);
      }
    } else if (mood === 'flickering') {
      retrigger(wildBody, 'flicker', 900);
      fx?.embers(W, 8, { pal: 'violet', life: 1.0 });
      fx?.crackleAround(W, { r: 12, n: 2, ms: 400 });
    } else {
      retrigger(wildBody, 'look', 1400);
    }
    if (ev.wild) {
      later(u, 120 * k, () => {
        floatText(st, numX + 4, numY + 10, `${(ev.wild > 0) === (sign > 0) ? '+' : '−'}${Math.abs(ev.wild)} ${label}`, bad ? 'bad' : 'good');
        meterTo(after.meter, 380);
      });
    }
    if (ev.drain) {
      // it comes at you: a crouch, a lunge toward the camera, a bolt of Violet Crackle onto your Evochi
      later(u, 260 * k, () => {
        retrigger(wildBody, 'lunge', 900);
        let hurtOnce = false;
        const hurt = () => {
          if (hurtOnce) return;
          hurtOnce = true;
          hitstop(st, 80 * k);
          setPet(ctx, st, 'surprised');
          retrigger(petBody, 'hurt', 750);
          fx?.flashAt(P, { size: 30, life: 0.3, pal: 'violet' });
          fx?.hollowShards(P, 8, 0.7);
          fx?.smoke([P[0], P[1] + 6], 6, { scale: 0.9 });
          punch(st, 'pet');
          later(u, 80 * k, () => shake(st, false, rm));
          ctx.sfx('enc_surge', 0.35);
        };
        later(u, 150 * k, () => {
          shot(st, 'pet', false, 'fast');
          ctx.sfx('enc_whoosh', 0.5);
          fx?.smoke(WF, 4, { scale: 0.7 });
          if (fx) {
            fx.crackle(WF, P, { ms: 320 * k, width: 1.1, jag: 4, segs: 10, branches: 3 });
            later(u, 70 * k, () => fx.crackle(WF, [P[0] + 2, P[1] + 3], { ms: 240 * k, width: 0.7, jag: 5, segs: 9, branches: 2 }));
            later(u, 60 * k, hurt);
          } else later(u, 120 * k, hurt);
        });
        later(u, 440 * k, () => {
          hurt();
          floatText(st, P[0], P[1] + 4, `${ev.drain} Energy`, 'bad');
          energyTo(after.energy, 380);
        });
      });
    }
  });
  later(u, replyAt + (ev.drain ? 1700 : 1100) * k, () => {
    shot(st, 'wide');
    u.busy = false;
    u.disp = null;
    u.holdPet = false;
    u.holdWild = false;
    ctx.rerender();
  });
}

// the last turn: the Hollow cracks, sheds its crystals and dissolves into motes of light, and the
// creature comes back in a burst; or a befriended one bounces with hearts. Then the outro and the result.
function finishChoreo(ctx, st, before, after) {
  const u = ctx.ui('encounter');
  const g = u.geom;
  const rm = ctx.app.reducedMotion;
  const fx = fxOf(st);
  const W = [g.wild.cx, g.wild.cy];
  const WF = g.wild.face || [W[0], g.wild.headY + 6];
  const P = g.pet.head;
  const wildBody = st.querySelector('.enc-wild');
  const restore = before.goal !== 'befriend';
  const wildH = (g.wild.width * g.ar) / g.wild.ar;
  const box = { x: g.wild.left + g.wild.width * 0.15, y: g.wild.headY, w: g.wild.width * 0.7, h: g.wild.top + wildH * (g.wild.gy / 100) - g.wild.headY };
  const fl = finalLog(after);
  setLog(ctx, fl.title, fl.sub, 'wild');
  const from = u.disp?.meter ?? before.meter;
  tween(350, (t) => {
    if (!u.disp) return;
    u.disp.meter = from + (after.meter - from) * t;
    syncStage(ctx, st, before);
  });
  ctx.music('none');
  shot(st, 'wild');
  const done = (ms) => later(u, ms, () => {
    u.busy = false;
    u.disp = null;
    u.holdPet = false;
    u.holdWild = false;
    u.phase = 'outro';
    ctx.rerender();
  });
  const confetti = () => {
    fx?.burst(W, 26, { shape: 'petal', pal: 'pink', blend: 'source-over', speed: 62, vary: 0.6, drag: 1.9, size: 2.6, sizeK: 'hold', alphaK: 'hold', life: 1.7, gravity: 42, spin: 7, angle: -Math.PI / 2, spread: 1.3 });
    fx?.burst(W, 14, { shape: 'sparkle', pal: 'gold', speed: 70, vary: 0.6, drag: 2, size: 3.4, sizeK: 'spark', life: 1.2, gravity: 50, spin: 2, angle: -Math.PI / 2, spread: 1.4 });
  };
  if (restore && fx && !rm) {
    ctx.sfx('enc_glow', 0.6);
    retrigger(wildBody, 'dissolve', 580);
    fx.hollowShards(W, 16, 1.2);
    fx.crackleAround(W, { r: 16, n: 4, ms: 400 });
    fx.dissolve(box, { n: 72, ms: 520, pal: 'gold' });
    fx.rays(W, { n: 9, r: 58, ms: 2400, pal: 'gold', alpha: 0.5 });
    fx.halo(W, { size: 64, life: 1.3, pal: 'gold', layer: 'back', alpha: 0.9 });
    later(u, 580, () => {
      setWild(st, after.creature.id, after.stateKey);
      st.classList.remove('hollow', 'phase2');
      st.classList.add('won');
      retrigger(wildBody, 'pop', 700);
      ctx.sfx('evolve_fanfare', 0.8);
      flash(st, 'gold');
      punch(st, 'wild', true);
      fx.ring(W, { r0: 4, r1: 52, ms: 720, pal: 'gold', width: 3 });
      fx.goldenPulse(W, { r1: 36, ms: 900, arms: 4, width: 2 });
      fx.shards(W, 26, 'gold', 1.3);
      confetti();
      later(u, 100, () => shake(st, false, rm));
      syncStage(ctx, st, after);
    });
    later(u, 1250, () => {
      setPet(ctx, st, 'excited');
      retrigger(st.querySelector('.enc-pet'), 'hop', 1200);
      fx.hearts(P, 3, { spread: 4 });
    });
    done(1900);
    return;
  }
  setWild(st, after.creature.id, after.stateKey);
  st.classList.remove('hollow', 'phase2');
  st.classList.add('won');
  ctx.sfx('evolve_fanfare', 0.8);
  flash(st, 'gold');
  fx?.halo(W, { size: 56, life: 1.4, pal: 'gold', layer: 'back', alpha: 0.9 });
  fx?.rays(W, { n: 8, r: 52, ms: 2200, pal: 'gold', alpha: 0.45 });
  fx?.ring(W, { r0: 4, r1: 46, ms: 700, pal: 'gold', width: 2.6 });
  fx?.healing(WF, { n: 12, w: 26, h: 20, pal: 'gold' });
  fx?.hearts(WF, 7, { spread: 9 });
  confetti();
  retrigger(wildBody, 'joy', 1800);
  syncStage(ctx, st, after);
  later(u, 900, () => {
    setPet(ctx, st, 'excited');
    retrigger(st.querySelector('.enc-pet'), 'hop', 1200);
    fx?.hearts(P, 3, { spread: 4 });
  });
  done(1400);
}

function setLog(ctx, title, sub, who) {
  const u = ctx.ui('encounter');
  const v = ctx.d.trails?.encounter;
  u.log = { title, sub, who, seed: v?.seed };
  const card = document.querySelector('.enc-log');
  if (!card) return;
  const hollow = v?.creature?.kind === 'hollow';
  card.dataset.who = who;
  const ic = card.querySelector('.lg-ic');
  if (ic) {
    ic.className = `lg-ic ${who === 'wild' && hollow ? 'hollow' : who}`;
    ic.innerHTML = who === 'wild' && hollow ? SI.hollow : who === 'wild' ? SI.leaf : SI.spark;
  }
  const t = card.querySelector('.line .t');
  const s = card.querySelector('.line .s');
  if (t) t.textContent = title;
  if (s) s.textContent = sub || '';
  retrigger(card, 'pop', 400);
}

/** A short toast on the shot (the board's Encounter Announcements). */
function announce(st, text, tone = 'calm') {
  const box = st?.querySelector('.enc-ann');
  if (!box || !text) return;
  const el = document.createElement('div');
  el.className = 'ann ' + tone;
  el.innerHTML = `<span class="ai">${ANN_IC[tone] || SI.spark}</span><span>${esc(text)}</span>`;
  box.appendChild(el);
  while (box.children.length > 3) box.firstChild.remove();
  setTimeout(() => el.classList.add('out'), 1900);
  setTimeout(() => el.remove(), 2350);
}

/** A log line with the names in bold, like the board. */
function logHTML(ctx, text) {
  const names = [ctx.d.trails?.encounter?.creature?.name, ctx.state.pet?.name].filter(Boolean);
  let s = esc(text || '');
  for (const n of names) s = s.split(esc(n)).join(`<b>${esc(n)}</b>`);
  return s;
}

// ------------------------------------------------------------------ status effects
/** The status chips, read from the real state (the board's mini-library, where the rules have one). */
function statuses(ctx, v, u) {
  const C = v.creature;
  const W = [];
  const P = [];
  if (v.done) return { W, P };
  if (C.kind === 'hollow') W.push({ id: 'hollowed', name: 'Hollowed', text: 'Lumen Glow is 30% stronger against the Hollow.' });
  if (v.phase2) W.push({ id: 'waking', name: 'Waking', text: 'It lashes out more often now. Keep your Energy up.' });
  if (v.mood === 'surging' && C.kind === 'hollow') W.push({ id: 'unsteady', name: 'Unsteady', text: 'Hollow energy is surging through it.' });
  if (v.mood === 'flickering') W.push({ id: 'flicker', name: 'Flickering', text: 'Its Hollow is loosening.' });
  if (v.goal === 'befriend') {
    if (v.mood === 'wary') W.push({ id: 'wary', name: 'Wary', text: 'It may skitter away. Gifts and patience help.' });
    if (v.curious) W.push({ id: 'trust', name: 'Curious', text: 'Gentle Nudge adds +4 Calm while it’s curious.' });
    if (v.mood === 'calm') W.push({ id: 'soothed', name: 'Soothed', text: 'It feels at ease with you.' });
  }
  if (v.phase2) P.push({ id: 'charged', name: 'Lumen Charged', text: 'Lumen Glow is 25% stronger now.' });
  const energy = u.disp?.energy ?? v.energy;
  if (energy < TR.ACTIONS.lumen_glow.energy) P.push({ id: 'tired', name: 'Tired', text: 'Not enough Energy for Lumen Glow. Soothe to rest.' });
  if (v.actions.some((a) => a.kind === 'companion' && a.can)) P.push({ id: 'bloom', name: 'Petalune is with you', text: 'Petal Hush is ready, once this encounter.' });
  return { W, P };
}

function chipHTML(s, fresh) {
  return `<button class="st-chip t-${s.id} ${fresh ? 'new' : ''}" data-act="status" data-arg="${s.id}" aria-label="${esc(s.name)}: ${esc(s.text)}" title="${esc(s.name)}">${SI[s.id] || SI.spark}</button>`;
}

function syncStatus(ctx, st, v) {
  const u = ctx.ui('encounter');
  const { W, P } = statuses(ctx, v, u);
  u.statusInfo = Object.fromEntries([...W, ...P].map((s) => [s.id, s]));
  const turn = st.querySelector('.enc-goalpill .tn');
  if (turn) turn.textContent = v.done ? 'Done' : `Turn ${v.turn + 1}`;
  const sig = W.map((s) => s.id).join(',') + '|' + P.map((s) => s.id).join(',');
  if (st.dataset.sig === sig) return;
  const old = new Set((st.dataset.sig || '').split(/[|,]/));
  st.dataset.sig = sig;
  const wc = st.querySelector('.enc-under .chips');
  const pc = st.querySelector('.pet-chips');
  if (wc) wc.innerHTML = W.map((s) => chipHTML(s, !old.has(s.id))).join('');
  if (pc) pc.innerHTML = P.map((s) => chipHTML(s, !old.has(s.id))).join('');
}

// ------------------------------------------------------------------ the panel
function actionStyle(a) {
  return { light: ['sun', 'sun'], physical: ['orange', 'nudge'], restore: ['teal', 'calm'], item: ['cream', 'bag'], companion: ['green', 'creature_petalune'] }[a.kind] || ['cream', a.icon];
}

/** The second line of an action button: what it costs (the board's clear action hierarchy). */
function actionSub(a, v) {
  if (a.kind === 'item') {
    const n = v.items.reduce((t, i) => t + i.qty, 0);
    return n ? `${n} available` : 'Nothing useful yet';
  }
  if (a.kind === 'restore') return '+30 Energy';
  if (a.kind === 'companion') return v.companionUsed ? 'Used this time' : 'Once · no Energy';
  return `−${a.energy} Energy`;
}

function actionLong(a, v) {
  const L = v.meterLabel;
  if (a.kind === 'restore') return `${a.name}: +30 Energy and a little ${L === 'Calm' ? 'Calm' : 'less Instability'}`;
  if (a.kind === 'item') return `${a.name}: ${actionSub(a, v)}`;
  return `${a.name}: ${v.goal === 'befriend' ? '+' : '−'}${a.power} ${L}${a.energy > 0 ? `, costs ${a.energy} Energy` : ''}`;
}

function playPanel(ctx, v, u, hidden = false) {
  const lg = currentLog(ctx, v, u);
  const hollow = v.creature.kind === 'hollow';
  const comp = v.actions.find((a) => a.kind === 'companion');
  const main = v.actions.filter((a) => a.kind !== 'companion');
  const icn = lg.who === 'wild' && hollow ? 'hollow' : lg.who;
  return html`<div class="enc-panel ${hidden ? 'offstage' : ''} ${u.busy ? 'busy' : ''}" ${hidden ? raw('aria-hidden="true" inert') : ''}>
    <button class="enc-log" data-act="log" data-k="log" data-who="${lg.who}" aria-expanded="${u.logOpen ? 'true' : 'false'}" aria-live="polite">
      ${u.logOpen ? html`<ol class="hist">${v.log.slice(-6, -1).map((l) => html`<li class="${l.who}">${raw(logHTML(ctx, l.text))}</li>`)}</ol>` : ''}
      <span class="lg-ic ${icn}" aria-hidden="true">${raw(icn === 'hollow' ? SI.hollow : icn === 'wild' ? SI.leaf : SI.spark)}</span>
      <p class="line"><b class="t">${lg.title}</b><span class="s">${lg.sub || ''}</span></p>
      <span class="chev" aria-hidden="true"></span></button>
    <div class="enc-actions">
      ${main.map((a) => {
        const [cls, ic] = actionStyle(a);
        return html`<button class="enc-act ${cls} ${a.kind}" data-act="do" data-arg="${a.id}" data-k="act-${a.id}" ${a.can && !u.busy && !v.done ? '' : raw('disabled')} aria-label="${actionLong(a, v)}">
          <span class="ic"><img src="${icon(ic)}" alt=""></span>
          <span class="tx"><b>${a.name}</b><small>${actionSub(a, v)}</small></span></button>`;
      })}
    </div>
    <div class="enc-foot ${comp ? 'has-comp' : ''}">
      ${comp ? html`<button class="enc-comp" data-act="do" data-arg="${comp.id}" data-k="act-${comp.id}" ${comp.can && !u.busy && !v.done ? '' : raw('disabled')} aria-label="${actionLong(comp, v)}, once this encounter">
        <img src="${icon('creature_petalune')}" alt=""><span><b>${comp.name}</b><small>${actionSub(comp, v)}</small></span></button>` : ''}
      <button class="enc-retreat" data-act="retreat-confirm" data-k="retreat" ${u.busy || v.done ? raw('disabled') : ''}>${raw(RUNNER)}<span>Retreat</span></button>
    </div>
  </div>`;
}

/** The title stacks: "A Wild / Petalune / Appeared!", "The Forgotten / Sentinel / Awakens!". */
function introTitle(v) {
  const C = v.creature;
  if (C.boss) {
    const w = C.name.split(' ');
    return [`The ${w.slice(0, -1).join(' ')}`, w[w.length - 1], 'Awakens!'];
  }
  if (C.kind === 'hollow' && C.name.startsWith('Hollow ')) return ['A Hollow', C.name.slice(7), 'Appeared!'];
  return ['A Wild', C.name, 'Appeared!'];
}

function introCard(ctx, v) {
  const C = v.creature;
  const [a, big, z] = introTitle(v);
  const goal = v.goal === 'befriend' ? 'Earn its trust' : 'Restore its light';
  return html`<div class="enc-panel intro ${C.kind} ${C.boss ? 'boss' : ''}">
    <h2 class="big-title"><span class="a">${a}</span><span class="big">${big}</span><span class="z">${z}</span></h2>
    <div class="ic-goal"><span class="gi">${raw(v.goal === 'befriend' ? SI.leaf : SI.sun)}</span><span>Goal: <b>${goal}</b></span></div>
    <p class="ic-text">${INTRO_LINES[C.id] || C.blurb}</p>
    <button class="enc-cta gold" data-act="begin" data-autofocus data-k="begin"><span>Begin Encounter</span></button>
    <button class="enc-retreat light" data-act="retreat-confirm" data-k="g-retreat">${raw(RUNNER)}<span>Not yet</span></button>
  </div>`;
}

function resultTitle(v) {
  const C = v.creature;
  if (v.goal === 'befriend') return [C.name, 'Is Calmed!', 'You earned its trust!', SI.leaf];
  if (C.boss) return [theName(C), 'Is Restored!', 'Its light returns. The old trail is open.', SI.sun];
  return [C.name, 'Is Restored!', 'Its light is back!', SI.sun];
}

function resultTiles(v) {
  const C = v.creature;
  const r = Q.QUESTS[v.quest].rewards;
  const t = [{ img: icon('creature_' + C.id), b: C.name.replace(/^Forgotten /, ''), s: v.goal === 'befriend' ? 'Now trusts you!' : 'Restored!', hl: true }];
  for (const id of r.items || []) t.push({ img: itemImg(id), b: ITEMS[id].name, s: 'Keepsake' });
  if (r.coins) t.push({ img: icon('coin'), b: `+${r.coins}`, s: 'EvoCoins' });
  for (const [id, n] of Object.entries(r.gifts || {})) t.push({ img: itemImg(id), b: `+${n}`, s: ITEMS[id].name });
  for (const id of r.titles || []) t.push({ img: icon('crown'), b: Q.TITLES[id].name, s: 'Title' });
  return t;
}

function resultPanel(ctx, v) {
  const [big, z, sub, ic] = resultTitle(v);
  const used = Object.entries(v.used);
  return html`<div class="enc-panel result ${v.goal}">
    <section class="rs-card" lang="en">
      <h2 class="big-title small"><span class="big">${big}</span><span class="z">${z}</span></h2>
      <p class="rs-sub"><span class="gi">${raw(ic)}</span><span>${sub}</span></p>
      <h3>Rewards</h3>
      <div class="rs-tiles">${resultTiles(v).map((t) => html`<div class="rs-tile ${t.hl ? 'hl' : ''}"><span class="pic"><img src="${t.img}" alt=""></span><b>${t.b}</b><small>${t.s}</small></div>`)}</div>
      <small class="rs-meta">${v.turn} turn${v.turn === 1 ? '' : 's'}${used.length ? ' · ' + used.map(([id, n]) => `${ITEMS[id].name}${n > 1 ? ' ×' + n : ''}`).join(', ') : ''}</small>
    </section>
    <button class="enc-cta" data-act="finish" data-autofocus data-k="finish"><span>Continue</span>${raw('<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12h13M13 6l6 6-6 6" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"/></svg>')}</button>
  </div>`;
}

/** The reward toasts as the result comes in (the board's Reward Toast), one after another. */
function rewardToasts(ctx, st, v) {
  const r = Q.QUESTS[v.quest].rewards;
  const list = [];
  if (r.companion) list.push({ img: icon('creature_' + r.companion), text: `${TR.CREATURES[r.companion].name} joined your team!` });
  for (const id of r.items || []) list.push({ img: itemImg(id), text: `${ITEMS[id].name} obtained!` });
  for (const id of r.titles || []) list.push({ img: icon('crown'), text: `${Q.TITLES[id].name} title earned!` });
  for (const x of r.unlocks || []) list.push({ img: icon('star'), text: `${x} unlocked!` });
  const box = st.querySelector('.enc-toast');
  if (!box) return;
  list.slice(0, 3).forEach((t, i) => setTimeout(() => {
    if (!box.isConnected) return;
    const el = document.createElement('div');
    el.className = 'rt';
    el.innerHTML = `<span class="ri"><img src="${t.img}" alt=""></span><b>${esc(t.text)}</b><i class="sp a"></i><i class="sp b"></i><i class="sp c"></i>`;
    box.appendChild(el);
    ctx.sfx('reward_chime', 0.4);
    setTimeout(() => el.classList.add('out'), 2300);
    setTimeout(() => el.remove(), 2750);
  }, 350 + i * 2500));
}

// ------------------------------------------------------------------ the screen
export const encounter = {
  id: 'encounter',
  scene: () => null,
  render(ctx) {
    const v = ctx.d.trails?.encounter;
    const u = ctx.ui('encounter');
    const pet = ctx.state.pet;
    if (!v || !pet) {
      setTimeout(() => ctx.go('guild', {}, { replace: true }), 0);
      return html`<main class="screen paper"></main>`;
    }
    if (u.seed !== v.seed) {
      // a new attempt: fresh stage, fresh timeline
      clearTimers(u);
      Object.assign(u, { seed: v.seed, busy: false, disp: null, holdPet: false, holdWild: false, logOpen: false, introStarted: false });
      if (!u.phase) u.phase = 'play';
    }
    if (!u.phase) u.phase = 'play';
    if (v.done === 'success' && u.phase === 'play' && !u.busy) u.phase = 'outro';
    u.geom = shotGeometry(v, pet);
    const phase = u.phase;
    const C = v.creature;
    const panel = phase === 'intro' ? playPanel(ctx, v, u, true)
      : phase === 'card' ? introCard(ctx, v)
      : phase === 'result' ? resultPanel(ctx, v)
      : playPanel(ctx, v, u);
    return html`<main class="screen enc2 ${v.intro} ph-${phase} ${C.kind === 'hollow' ? 'hollow-kind' : 'wild-kind'} ${C.boss ? 'boss' : ''}" data-keep-root="enc:${v.seed}" aria-label="Encounter with ${C.name}">
      ${stageHTML(ctx, v, u.geom)}
      ${panel}
    </main>`;
  },
  mount(ctx, el) {
    const v = ctx.d.trails?.encounter;
    const u = ctx.ui('encounter');
    if (!v || !el) return;
    const st = stageEl(el);
    if (!st) return;
    // the visible part of the shot ends where the panel begins (it overlaps a little, rounded)
    const panel = el.querySelector('.enc-panel');
    const ph = panel ? panel.offsetHeight : 0;
    const view = st.querySelector('.enc-view');
    const bottom = u.phase === 'card' ? 0 : Math.max(0, ph - 20);
    if (view && view.style.bottom !== bottom + 'px') view.style.bottom = bottom + 'px';
    st.style.setProperty('--ph', `${bottom + 20}px`);
    ensureFX(ctx, st);
    syncStage(ctx, st, v);
    if (!st.dataset.init) {
      st.dataset.init = '1';
      // every expression ready before it is needed, so a blink or a flinch never waits on a decode
      const pet = ctx.state.pet;
      const ov = Object.values(pet.equipped || {});
      for (const ex of charEntry(pet.stage).battle?.expressions || []) battleSprite(pet.stage, pet.paletteId, ex, ov);
      if (!u.idleOn) {
        u.idleOn = true;
        scheduleIdle(ctx);
      }
      if (u.phase === 'intro' && !u.introStarted) {
        u.introStarted = true;
        playIntro(ctx, st, v);
      } else {
        // a fresh stage mid-encounter (came back from elsewhere, or a reload): no intro, just the shot
        st.classList.add('lit', 'eye-l', 'eye-r');
        if (u.phase === 'card' || u.phase === 'intro') shot(st, 'hero', true);
        else st.classList.add('pet-in');
        if (v.done === 'success') st.classList.add('won');
        ctx.music(u.phase === 'result' ? null : (INTRO[v.intro] || INTRO.standard).music);
        if (u.phase === 'intro') {
          clearTimers(u);
          u.phase = 'card';
          ctx.rerender();
        }
      }
    }
    if (u.phase === 'outro' && !u.outroTimer) {
      st.classList.add('won');
      u.outroTimer = later(u, ctx.app.reducedMotion ? 700 : 2400, () => {
        u.outroTimer = null;
        if (u.phase === 'outro') {
          u.phase = 'result';
          ctx.music(null);
          ctx.rerender();
        }
      });
    }
    if (u.phase === 'result' && !st.dataset.result) {
      st.dataset.result = '1';
      shot(st, 'wild');
      rewardToasts(ctx, st, v);
      // a speech bubble over the creature: a heart for a new friend, light for a restored one
      const g = u.geom;
      const WF = g.wild.face || [g.wild.cx, g.wild.headY + 6];
      vfx(st, 'speech ' + v.goal, WF[0] + g.wild.width * 0.06, g.wild.headY - 3, v.goal === 'befriend' ? SI.trust : SI.sun, 600000);
      fxOf(st)?.setAmbient('won', { x: g.wild.cx - 22, y: g.wild.headY - 8, w: 44, h: g.wild.bottom - g.wild.headY + 8 });
    }
  },
  actions: {
    'skip-intro'(ctx) {
      skipIntro(ctx);
    },
    begin(ctx) {
      const u = ctx.ui('encounter');
      u.phase = 'play';
      ctx.sfx('ui_tap', 0.4);
      const st = stageEl();
      if (st) {
        ctx.sfx('enc_whoosh', 0.45);
        st.classList.add('pet-in');
        shot(st, 'wide');
      }
      ctx.rerender();
    },
    status(ctx, id) {
      const s = ctx.ui('encounter').statusInfo?.[id];
      if (s) announce(stageEl(), `${s.name}: ${s.text}`, 'calm');
    },
    do(ctx, actionId) {
      if (ctx.ui('encounter').busy) return;
      if (actionId === 'item') return openItemPicker(ctx);
      runTurn(ctx, actionId, null);
    },
    log(ctx) {
      const u = ctx.ui('encounter');
      u.logOpen = !u.logOpen;
      ctx.rerender();
    },
    'retreat-confirm'(ctx) {
      ctx.modal({
        center: true,
        label: 'Retreat',
        render: () => html`<div class="stack center"><h2 class="h-sec">Leave for now?</h2><p class="body" style="margin:0">The encounter ends. Any items you used come back, and you can try again from the Guild whenever you like.</p>
          <button class="btn block" data-act="rt-yes" data-autofocus>Retreat</button><button class="btn cream block" data-act="modal-close">Stay</button></div>`,
        actions: {
          'rt-yes': (c) => {
            c.closeModal();
            const r = c.act(TR.encounterAct, 'retreat', null);
            if (!r.error) {
              const u = c.ui('encounter');
              clearTimers(u);
              clearTimeout(u.idleTimer);
              u.idleOn = false;
              u.phase = null;
              u.seed = null;
              c.music(null);
              c.go('guild', {}, { replace: true });
            }
          },
        },
      });
    },
    finish(ctx) {
      const v = ctx.d.trails.encounter;
      const qid = v.quest;
      const r = ctx.act(TR.completeEncounter);
      if (r.error) return;
      const u = ctx.ui('encounter');
      clearTimers(u);
      clearTimeout(u.idleTimer);
      u.idleOn = false;
      u.phase = null;
      u.seed = null;
      ctx.music(null);
      ctx.go('guild', {}, { replace: true });
      openStoryReward(ctx, qid, { then: 'stay' });
    },
  },
};

function openItemPicker(ctx) {
  ctx.modal({
    label: 'Use an item',
    render: (c) => {
      const v = c.d.trails.encounter;
      return html`<div class="stack">
        <h2 class="h-sec">Offer something</h2>
        ${v.items.length ? html`<div class="list">${v.items.map((it) => html`<button class="card row item-pick" data-act="pick" data-arg="${it.id}" data-k="pick-${it.id}"><img src="${itemImg(it.id)}" alt="" width="48" height="48"><div class="grow" style="text-align:left"><b class="h-card">${it.name} <span class="tag small cream">×${it.qty}</span></b><div class="small muted">${v.goal === 'befriend' ? '+' : '−'}${it.amount} ${v.meterLabel}${it.liked ? html` · <b style="color:var(--gold-900)">${v.creature.name} loves this</b>` : ''}</div></div></button>`)}</div>`
          : html`<p class="body" style="margin:0">Nothing in your Bag helps here yet. Homemade food calms wild Evochi; tonics and Glowleaf steady the Hollow.</p>`}
        <button class="btn cream block" data-act="modal-close">Back</button></div>`;
    },
    actions: {
      pick: (c, id) => {
        c.closeModal();
        runTurn(c, 'item', id);
      },
    },
  });
}

// ------------------------------------------------------------------ prep
function checkRow(done, text, opt = false) {
  return html`<li class="${done ? 'done' : ''} ${opt ? 'opt' : ''}"><span class="box" aria-hidden="true">${done ? ICON.check : ''}</span><span>${text}</span>${opt ? html`<em>optional</em>` : ''}</li>`;
}

export const prep = {
  id: 'prep',
  scene: () => null,
  render(ctx) {
    const qid = TR.ENCOUNTERS[ctx.app.route.params.id] ? ctx.app.route.params.id : 'eq01';
    const E = TR.ENCOUNTERS[qid];
    const C = TR.CREATURES[E.creature];
    const v = Q.questView(ctx.state, qid, ctx.now);
    const n = v.next;
    const t = Q.QUESTS[qid].turnIns.find((x) => x.encounter);
    const pet = ctx.state.pet;
    const giver = Q.NPCS[Q.QUESTS[qid].giver];
    const walkDone = v.walk && v.phase !== Q.QUESTS[qid].walk.phase && v.accepted;
    const needs = Q.itemNeeds(ctx.state, t);
    const opts = Object.entries(t.optionalItems || {}).map(([id, nn]) => ({ id, need: nn, have: G.ownedQty(ctx.state, id), ok: G.ownedQty(ctx.state, id) >= nn }));
    const ready = n.kind === 'encounter';
    const stageOk = (pet?.stage || 1) >= (E.recommended.stage || 1);
    const going = n.kind === 'gather' ? needs.find((x) => !x.ok) : null;
    const src = going ? H.homeSource(going.id) : null;
    const place = PLACE_INFO[E.place] || { name: TR.PLACE_NAMES[E.place], line: '', badge: 'trail' };
    const sc = TM().scenes[E.scene];
    const u = ctx.ui('prep');
    const recs = E.recommended.items;
    const owned = recs.filter((id) => G.ownedQty(ctx.state, id) > 0);
    const recId = u.rec != null ? recs[u.rec % recs.length] : owned[0] || recs[0];
    const fx = TR.itemEffect(recId, E.goal, E.creature);
    const have = G.ownedQty(ctx.state, recId);
    const recSrc = have ? null : H.homeSource(recId);
    const comps = ctx.d.trails.companions.filter((c) => c.id !== E.creature);
    const goalLine = E.goal === 'befriend' ? `Calm a wild ${C.name} in the ${place.name}.` : `Restore ${C.name.startsWith('Forgotten') ? 'the ' + C.name : 'the ' + C.name} at ${place.name.replace(/^The /, 'the ')}.`;
    const lvl = Q.QUESTS[qid].level || 1;
    const sign = E.goal === 'befriend' ? '+' : '−';
    const label = E.goal === 'befriend' ? 'Calm' : 'Instability';
    const approach = E.goal === 'befriend'
      ? { icon: 'calm', name: 'Calm', text: `Gifts ${C.name} loves count 1.5×. A Gentle Nudge makes it curious.` }
      : { icon: 'sun', name: 'Lumen', text: 'Lumen Glow is 30% stronger against the Hollow.' };
    const ARROW = raw('<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 5l7 7-7 7" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>');
    const maxE = TR.maxEnergy(ctx.state);
    return html`<main class="screen scroll paper prep2 ${C.kind}" aria-label="Encounter preparation">
      <header class="prep-head2">
        <button class="pb" data-act="back" aria-label="Back" data-k="tback">${ICON.back}</button>
        <h1>Encounter Preparation</h1>
        <button class="pb map" data-act="place" aria-label="Look around ${place.name}" data-k="p-place"><img src="${icon('trail')}" alt=""></button>
      </header>
      <div class="prep-body">
        <div class="prep-banner"><img src="${url(sc.file)}" alt=""><span class="pb-place"><img src="${icon(place.badge)}" alt="">${place.name}</span></div>
        <section class="prep-plate ${C.kind}" aria-label="${C.name}">
          <span class="np-face ${C.kind === 'hollow' ? 'hollow' : ''}"><img src="${icon('creature_' + C.id)}" alt=""></span>
          <div class="pp-id"><b>${C.name}</b><small>${RARITY[C.rarity] || ''} · ${C.kind === 'hollow' ? 'Hollow' : TR.AFFINITIES[C.affinity].name}</small></div>
          <span class="pp-lv">Lv. ${lvl}</span>
          <div class="pp-meter"><div class="np-bar thin ${E.goal === 'befriend' ? 'calm' : 'inst'}"><i style="width:${E.goal === 'befriend' ? '0%' : '100%'}"></i></div><b>${E.goal === 'befriend' ? 0 : E.meter} / ${E.meter}</b></div>
        </section>
        <h3 class="prep-h">Objective</h3>
        <section class="prep-obj">
          <p>${goalLine} ${E.goal === 'befriend' ? 'Earn its trust, and it may join your journey.' : 'Calm the Hollow energy and bring its light back.'}</p>
          <ul class="checks">
            ${v.phase === 'available' || v.phase === 'locked' ? checkRow(false, v.phase === 'locked' ? v.lock.text : `Accept the job from ${giver.name}`) : checkRow(true, `Job accepted from ${giver.name}`)}
            ${v.walk ? checkRow(!!walkDone, walkDone ? `Reach ${place.name}` : `Walk ${fmt(v.resolved)} steps to ${place.name} · ${fmt(v.walk.progress || 0)} so far`) : ''}
            ${needs.map((x) => checkRow(x.ok, `Bring ${x.need} × ${ITEMS[x.id].name} (${x.have}/${x.need})`))}
            ${opts.map((x) => checkRow(x.ok, `Bring ${ITEMS[x.id].name} for a better start`, true))}
          </ul>
        </section>
        <h3 class="prep-h">Recommended</h3>
        <div class="prep-recs">
          <section class="rec-tile">
            <small class="rk">Suggested Item</small>
            <span class="rpic"><img src="${itemImg(recId)}" alt=""></span>
            <b>${ITEMS[recId].name}</b>
            ${fx ? html`<span class="rp ${E.goal}">${sign}${fx.amount} ${label}</span>` : ''}
            <small>${have ? `You have ${have}` : 'You have none yet'}${fx?.liked ? ` · ${C.name} loves it` : ''}</small>
            ${!have && recSrc ? html`<button class="mini" data-act="home" data-arg="${recSrc.route === 'station' ? recSrc.station : 'garden'}" data-k="rec-make">${recSrc.verb}</button>`
              : recs.length > 1 ? html`<button class="mini" data-act="rec-next" data-k="rec-next">Change</button>` : ''}
          </section>
          <section class="rec-tile">
            <small class="rk">Suggested Approach</small>
            <span class="rpic"><img src="${icon(approach.icon)}" alt=""></span>
            <b>${approach.name}</b>
            <small>${approach.text}</small>
          </section>
        </div>
        <h3 class="prep-h">Your Team <button class="help" data-act="team-help" aria-label="About your team" data-k="team-help">?</button></h3>
        <section class="team-list">
          ${pet ? html`<div class="tm-row ${stageOk ? '' : 'warn'}"><span class="np-face pet"><img data-sprite="${spriteAttr(pet.stage, pet.paletteId, 'happy', [], '', 90)}" src="${BLANK}" alt=""></span>
            <div class="tm-id"><b>${pet.name}</b><small>Lv. ${ctx.d.pet.level} · ${stageLabel(pet.stage)}</small></div>
            <div class="tm-meter"><span>Energy</span><div class="np-bar thin energy"><i style="width:100%"></i></div><b>${maxE} / ${maxE}</b></div></div>` : ''}
          ${comps.map((c) => html`<div class="tm-row"><span class="np-face"><img src="${icon('creature_' + c.id)}" alt=""></span>
            <div class="tm-id"><b>${c.name}</b><small>${c.companion?.name || 'Companion'} · once per encounter</small></div><span class="tm-tag">Ready</span></div>`)}
          ${!comps.length ? html`<div class="tm-row ghost"><span class="np-face q">?</span><div class="tm-id"><b>Companion</b><small>Befriend one to help in encounters</small></div></div>` : ''}
        </section>
        ${!stageOk ? html`<p class="prep-note">A ${stageLabel(E.recommended.stage)} or older Evochi has more Energy for this one. You can still go.</p>` : ''}
        <div class="prep-cta">
          ${ready ? html`<button class="enc-cta gold big" data-act="travel" data-k="travel"><span>Begin Encounter</span>${ARROW}</button>`
            : v.phase === 'available' ? html`<button class="enc-cta big alt" data-act="talk" data-k="talk"><span>Talk to ${giver.name}</span></button>`
            : n.kind === 'walk' ? html`<button class="enc-cta big" data-act="walk" data-k="p-walk"><span>Go for a walk</span></button>`
            : going && src ? html`<button class="enc-cta big" data-act="home" data-arg="${src.route === 'station' ? src.station : 'garden'}" data-k="p-home"><span>${src.verb} ${ITEMS[going.id].name} in your ${src.place}</span></button>`
            : v.completed ? html`<div class="prep-done">${E.goal === 'befriend' ? `${C.name} is your companion.` : `${C.name} was restored.`}</div>` : ''}
          <button class="enc-link" data-act="quest" data-arg="${qid}" data-k="p-details">Quest details</button>
        </div>
      </div>
    </main>`;
  },
  actions: {
    back(ctx) {
      ctx.back();
    },
    quest(ctx, id) {
      openStoryQuest(ctx, id);
    },
    place(ctx) {
      const E = TR.ENCOUNTERS[ctx.app.route.params.id] || TR.ENCOUNTERS.eq01;
      ctx.go('trailplace', { id: E.place });
    },
    'rec-next'(ctx) {
      const u = ctx.ui('prep');
      u.rec = (u.rec || 0) + 1;
      ctx.rerender();
    },
    'team-help'(ctx) {
      ctx.modal({
        center: true,
        label: 'Your team',
        render: () => html`<div class="stack center"><h2 class="h-sec">Your team</h2><p class="body" style="margin:0">Your Evochi takes the turns. A grown Evochi has more Energy (100 as an Eggling, 120, then 140). Befriended companions lend one ability per encounter, like Petalune’s Petal Hush.</p><button class="btn block" data-act="modal-close" data-autofocus>Got it</button></div>`,
      });
    },
    travel(ctx) {
      const qid = ctx.app.route.params.id;
      const r = ctx.act(TR.startEncounter, qid);
      if (r.error) return;
      const u = ctx.ui('encounter');
      u.phase = null;
      u.seed = null;
      ctx.go('travel', { id: qid });
    },
    talk(ctx) {
      const qid = ctx.app.route.params.id;
      const g = Q.QUESTS[qid].giver;
      ctx.go('place', { id: Q.NPCS[g].location, npc: g });
    },
    walk(ctx) {
      ctx.app.ui.journey = { ...(ctx.app.ui.journey || {}), tab: 'daily' };
      ctx.app.tab('journey');
    },
    home(ctx, where) {
      if (where === 'kitchen' || where === 'apothecary') ctx.go('station', { id: where });
      else ctx.go(where);
    },
  },
};

