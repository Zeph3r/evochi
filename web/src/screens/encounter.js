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

const TM = () => manifest().trails;
const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
const pct = (x) => `${Math.round(x * 1000) / 10}%`;

// your Evochi's frame width (share of the shot's width) per stage, and how far right its face may reach
const PET_W = { 1: 0.44, 2: 0.52, 3: 0.68 };
const FACE_MAX_X = 0.38;
// lift your Evochi off the scene's mark a little, so its card below covers only its feet
const PET_LIFT = 0.075;
const INTRO = {
  rare: { ms: 4300, music: 'enc_wild_loop', title: (C) => `A wild ${C.name} appeared!`, sub: 'Something rare is watching you.' },
  hollow: { ms: 4900, music: 'enc_boss_loop', title: (C) => `${C.name} stirs…`, sub: 'Hollow energy pulses in the stones.' },
  boss: { ms: 8200, music: 'enc_boss_loop', title: (C) => `The ${C.name.replace(/^Forgotten /, '')} awakens`, sub: 'Guardian of the Lumen Trails' },
  standard: { ms: 2600, music: 'enc_wild_loop', title: (C) => `${C.name} peeks out`, sub: '' },
};
const PLACE_INFO = {
  ruins: { name: 'Mossy Ruins', line: 'A quiet grove with ancient light.', badge: 'aff_nature' },
  gate: { name: 'The Old Gate', line: 'The broken gate past the bridge.', badge: 'moon' },
};
const RARITY = { rare: 'Rare', uncommon: 'Uncommon', legendary: 'Legendary', common: 'Common' };
const RUNNER = '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="14.5" cy="4.2" r="2.2" fill="currentColor"/><path d="M10.2 8.6l3.6-1.1c.7-.2 1.4.1 1.8.7l1.6 2.6 2.6.9M12.6 8.1l-1.7 5 3.2 2.4-.9 5.1M10.9 13.1l-2.4 3.6-3.6.6M9.6 9.4L6.8 11" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
const PEAKS = '<svg viewBox="0 0 32 24" aria-hidden="true"><path d="M2 21L12 5l6 9 3-4 9 11z" fill="#2F6B3A"/><path d="M12 5l3 4.6-2.2-.9L11 10.4 9.6 8.9z" fill="#E9F6DC"/></svg>';
const HEART = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 21s-7.5-4.6-9.4-9.3C1.2 8.2 3.4 4.6 7 4.6c2.1 0 3.6 1.2 5 3 1.4-1.8 2.9-3 5-3 3.6 0 5.8 3.6 4.4 7.1C19.5 16.4 12 21 12 21z" fill="#F58CA6" stroke="#FFF" stroke-width="1.6"/></svg>';
const SPARK = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 1.5l2.4 8.1 8.1 2.4-8.1 2.4L12 22.5l-2.4-8.1L1.5 12l8.1-2.4z" fill="#FFF6C9" stroke="#F4B84E" stroke-width="1.2" stroke-linejoin="round"/></svg>';

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
  const wild = {
    left: (wl / W) * 100, top: (wt / Hh) * 100, width: ((CB.w * s) / W) * 100, ar: CB.w / CB.h,
    cx: (A.wild[0] / W) * 100, cy: ((A.wild[1] - (cg[1] - ct[1]) * s * 0.55) / Hh) * 100,
    face: CB.anchors.face ? [((wl + CB.anchors.face[0] * s) / W) * 100, ((wt + CB.anchors.face[1] * s) / Hh) * 100] : null,
    eyes: CB.anchors.eye_l ? [local(CB.anchors.eye_l), local(CB.anchors.eye_r)] : null,
    headY: ((wt + ct[1] * s) / Hh) * 100,
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

function badgeFor(C) {
  return C.kind === 'hollow' ? 'moon' : TR.AFFINITIES[C.affinity].icon;
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
  const sub = C.boss ? 'Legendary · Story boss' : `${RARITY[C.rarity] || ''}${hollowTheme ? ' · Hollow' : ` · ${A.name}`}`;
  const dust = Array.from({ length: 14 }, (_, i) => html`<i style="--i:${i};--x:${(i * 37) % 100}%"></i>`);
  return html`<div class="enc-stage" data-keep="stage:${v.seed}" data-shot="wide" style="--wx:${pct(g.wild.cx / 100)};--wy:${pct(g.wild.cy / 100)};--px:${pct(g.pet.cx / 100)};--py:${pct(g.pet.cy / 100)};--fx:${pct((g.wild.face?.[0] ?? g.wild.cx) / 100)};--fy:${pct((g.wild.face?.[1] ?? g.wild.cy) / 100)}">
    <div class="enc-view">
      <div class="enc-world" style="--ar:${g.ar}"><div class="enc-cam"><div class="enc-shake"><div class="enc-drift">
        <img class="enc-bg" src="${url(g.B.file)}" alt="">
        <div class="enc-aura" style="left:${pct(g.wild.cx / 100)};top:${pct(g.wild.cy / 100)}"></div>
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
        <div class="enc-vfx" aria-hidden="true"></div>
      </div></div></div></div>
      <div class="enc-grade" aria-hidden="true"></div>
      <div class="enc-flash" aria-hidden="true"></div>
      <div class="enc-dust" aria-hidden="true">${dust}</div>
      <section class="enc-plate wild-plate ${hollowTheme ? 'hollow' : ''}" aria-label="${C.name}">
        <span class="np-badge ${hollowTheme ? 'moon' : ''}"><img src="${icon(badgeFor(C))}" alt=""></span>
        <div class="np-id"><span class="np-sub">${sub}</span><b class="np-name">${C.name}</b></div>
        <span class="np-aff ${hollowTheme ? 'faded' : ''}"><img src="${icon(A.icon)}" alt="${A.name}"></span>
        ${meterHTML(v.goal === 'befriend' ? 'calm' : 'inst', v.meterLabel, v.meter / v.max, `${Math.round(v.meter)} / ${v.max}`)}
      </section>
      ${pet ? html`<section class="enc-plate pet-plate" aria-label="${pet.name}">
        <span class="np-badge swirl"><img src="${icon('swirl')}" alt=""></span>
        <div class="np-id"><b class="np-name">${pet.name}</b><span class="np-lv">Lv. ${ctx.d.pet.level}</span></div>
        ${meterHTML('energy', 'Energy', v.energy / v.energyMax, `${v.energy} / ${v.energyMax}`, false)}
      </section>` : ''}
      <div class="enc-ribbon" aria-live="polite"></div>
      <div class="enc-caption" aria-live="polite"></div>
    </div>
    <div class="enc-bars" aria-hidden="true"><i></i><i></i></div>
    <div class="enc-title" aria-live="polite"></div>
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

function shot(st, name, instant = false) {
  if (!st) return;
  if (instant) {
    st.classList.add('cut');
    st.dataset.shot = name;
    void st.offsetWidth;
    st.classList.remove('cut');
  } else st.dataset.shot = name;
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
  vfx(st, 'float ' + kind, x, y, esc(text), 1500);
}

/** Something travels from a to b (percent of the shot) along an arc; returns its flight time. */
function projectile(st, cls, a, b, inner, ms, arc = 0) {
  const el = vfx(st, 'proj ' + cls, 0, 0, `<span class="pv" style="left:${a[0]}%;top:${a[1]}%">${inner}</span>`, ms + 80,
    `--dx:${b[0] - a[0]};--dy:${b[1] - a[1]};--arc:${arc};--t:${ms}ms`);
  return el;
}

function burst(st, cls, p, n = 8, inner = '', life = 1100) {
  const html_ = Array.from({ length: n }, (_, i) => `<i style="--a:${(360 / n) * i + (i % 2) * 11}deg;--d:${0.7 + (i % 3) * 0.25}">${inner}</i>`).join('');
  vfx(st, 'burst ' + cls, p[0], p[1], html_, life);
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
}

// ------------------------------------------------------------------ intros (on the same shot)
function playIntro(ctx, st, v) {
  const u = ctx.ui('encounter');
  const rm = ctx.app.reducedMotion;
  const I = INTRO[v.intro] || INTRO.standard;
  const C = v.creature;
  const title = st.querySelector('.enc-title');
  ctx.app.root.classList.add('cinematic');
  const done = () => {
    ctx.app.root.classList.remove('cinematic');
    title.classList.remove('show');
    if (u.phase !== 'intro') return;
    u.phase = 'card';
    u.holdWild = false;
    u.holdPet = false;
    ctx.rerender();
  };
  const showTitle = () => {
    title.innerHTML = `<b>${esc(I.title(C))}</b>${I.sub ? `<span>${esc(I.sub)}</span>` : ''}`;
    retrigger(title, 'show');
  };
  if (rm) {
    shot(st, 'wide', true);
    st.classList.add('pet-in', 'lit');
    if (v.intro === 'boss') setWild(st, C.id, v.stateKey);
    ctx.music(I.music);
    showTitle();
    later(u, 1400, done);
    return;
  }
  st.classList.add('intro-' + v.intro);
  if (v.intro === 'boss') {
    // the Sentinel's awakening: dark and still, a rumble, its eyes light one after the other, the ruins
    // shake, your Evochi flinches, and the music turns before the encounter begins
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
    });
    later(u, 1100, () => shake(st, false));
    later(u, 1500, () => {
      ctx.sfx('enc_awaken', 0.9);
      st.classList.add('eye-l');
    });
    later(u, 2300, () => st.classList.add('eye-r'));
    later(u, 3300, () => {
      setWild(st, C.id, 'hollow');
      st.classList.add('lit');
    });
    later(u, 3850, () => {
      shake(st, true);
      flash(st, 'violet');
      burst(st, 'ring violet', [u.geom.wild.cx, u.geom.wild.cy], 1, '', 1400);
      shot(st, 'wide');
      st.classList.add('pet-in');
    });
    later(u, 4500, () => {
      setPet(ctx, st, 'surprised');
      retrigger(st.querySelector('.enc-pet'), 'flinch', 1100);
      ctx.sfx('pet_chirp', 0.5);
      ctx.music(I.music);
    });
    later(u, 5400, showTitle);
    later(u, I.ms, () => {
      st.classList.remove('trembling');
      u.holdPet = false;
      setPet(ctx, st, 'determined');
      done();
    });
    return;
  }
  // rare / hollow / standard: start close on the wild one, then pull back as your Evochi steps in
  shot(st, 'close', true);
  ctx.music(I.music);
  if (v.intro === 'hollow') {
    st.classList.add('silhouette');
    later(u, 500, () => {
      ctx.sfx('enc_surge', 0.6);
      burst(st, 'ring violet', [u.geom.wild.cx, u.geom.wild.cy], 1, '', 1400);
      shake(st, false);
    });
    later(u, 1500, () => st.classList.remove('silhouette'));
  } else {
    later(u, 900, () => {
      retrigger(st.querySelector('.enc-wild'), 'bang', 0);
      ctx.sfx('pet_chirp', 0.45);
    });
  }
  later(u, v.intro === 'hollow' ? 2000 : 1700, () => {
    shot(st, 'wide');
    st.classList.add('pet-in', 'lit');
    ctx.sfx('enc_whoosh', 0.5);
  });
  later(u, v.intro === 'hollow' ? 2900 : 2600, showTitle);
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
    st.classList.add('pet-in', 'lit', 'eye-l', 'eye-r');
    shot(st, 'wide', true);
    ctx.music((INTRO[v.intro] || INTRO.standard).music);
  }
  u.holdWild = false;
  u.holdPet = false;
  u.phase = 'card';
  ctx.rerender();
}

// ------------------------------------------------------------------ a turn, choreographed
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
  const youLine = after.log[before.log.length]?.text || '';
  const wildLine = after.log[after.log.length - 1]?.text || '';
  setLog(ctx, youLine, 'you');
  syncStage(ctx, st, before);
  setPet(ctx, st, 'determined');
  const W = [g.wild.cx, g.wild.cy];
  const P = g.pet.head;
  const petBody = st?.querySelector('.enc-pet');
  const wildBody = st?.querySelector('.enc-wild');
  let impact = 900;
  // 1-2. your move
  if (A.kind === 'light') {
    shot(st, 'pet');
    retrigger(petBody, 'cast', 900);
    ctx.sfx('enc_glow', 0.7);
    later(u, 380 * k, () => {
      projectile(st, hollow ? 'orb violet' : 'orb', P, W, '<i></i>', 520 * k, -6);
      shot(st, 'wild');
    });
    impact = 900 * k;
  } else if (A.kind === 'physical') {
    shot(st, 'pet');
    retrigger(petBody, 'lunge', 800);
    ctx.sfx('enc_whoosh', 0.6);
    later(u, 300 * k, () => shot(st, 'wild'));
    impact = 420 * k;
  } else if (A.kind === 'restore') {
    shot(st, 'pet');
    retrigger(petBody, 'rest', 1300);
    setPet(ctx, st, 'sleepy');
    ctx.sfx('enc_soothe', 0.6);
    burst(st, 'ring teal', [g.pet.cx, g.pet.cy], 1, '', 1200);
    for (let i = 0; i < 5; i++) later(u, i * 120 * k, () => vfx(st, 'rise', g.pet.cx + (i - 2) * 4, g.pet.cy - 4, HEART, 1300));
    later(u, 650 * k, () => {
      u.disp.energy = Math.min(before.energyMax, before.energy + 30);
      syncStage(ctx, st, before);
      floatText(st, g.pet.head[0], g.pet.head[1] + 4, '+30 Energy', 'energy');
    });
    later(u, 900 * k, () => shot(st, 'wide'));
    impact = 1150 * k;
  } else if (A.kind === 'item') {
    shot(st, 'pet');
    ctx.sfx('enc_whoosh', 0.5);
    const it = itemId ? `<img src="${itemImg(itemId)}" alt="">` : '';
    later(u, 200 * k, () => {
      projectile(st, 'toss', P, [W[0], W[1] + 4], it, 700 * k, -18);
      shot(st, 'wild');
    });
    impact = 920 * k;
  } else if (A.kind === 'companion') {
    shot(st, 'wide');
    vfx(st, 'buddy', 6, 70, `<img src="${icon('creature_petalune')}" alt="">`, 1900);
    ctx.sfx('enc_soothe', 0.6);
    for (let i = 0; i < 9; i++) later(u, (200 + i * 60) * k, () => projectile(st, 'petal', [4, 64 + (i % 3) * 6], [W[0] + (i % 3) * 3 - 3, W[1] + (i % 2) * 4], '<i></i>', 760 * k, -10 - (i % 4) * 4));
    impact = 1050 * k;
  }
  // 3. impact on the wild one
  later(u, impact, () => {
    u.disp.meter = mid;
    syncStage(ctx, st, before);
    if (A.kind === 'light') {
      burst(st, hollow ? 'spark violet' : 'spark', W, 9, '<i></i>');
      flash(st, hollow ? 'violet' : 'gold');
      ctx.sfx('reward_chime', 0.35);
    } else if (A.kind === 'physical') {
      burst(st, 'boop', [W[0] - 3, W[1] + 2], 6, SPARK);
      ctx.sfx('play_boing', 0.5);
    } else if (A.kind === 'item') {
      burst(st, 'boop', W, 6, ev.you >= 20 ? HEART : SPARK);
      ctx.sfx('pet_chirp', 0.45);
    } else {
      burst(st, 'boop soft', W, 5, A.kind === 'companion' ? HEART : SPARK);
    }
    if (A.kind !== 'restore' || ev.you) retrigger(wildBody, A.kind === 'restore' ? 'perk' : 'hit', 700);
    if (ev.you) floatText(st, W[0], g.wild.headY + 2, `${sign > 0 ? '+' : '−'}${ev.you} ${label}`, hollow ? 'good violet' : 'good');
  });
  // 4. the reply (or the finish)
  const replyAt = impact + 650 * k;
  if (after.done === 'success') {
    later(u, replyAt - 250 * k, () => finishChoreo(ctx, st, before, after));
    return;
  }
  later(u, replyAt, () => {
    setLog(ctx, wildLine, 'wild');
    const mood = ev.mood;
    const bad = ev.wild < 0;
    shot(st, mood === 'surging' || ev.drain ? 'wild' : 'wide');
    if (wildBody) wildBody.dataset.mood = mood || '';
    if (mood === 'wary') {
      retrigger(wildBody, 'skitter', 900);
      ctx.sfx('enc_whoosh', 0.35);
    } else if (mood === 'curious') {
      retrigger(wildBody, 'tilt', 900);
      vfx(st, 'bubble', W[0] + 6, g.wild.headY - 2, '?', 1300);
    } else if (mood === 'surging' || mood === 'waking') {
      ctx.sfx('enc_surge', 0.6);
      burst(st, 'ring violet', W, 1, '', 1200);
      retrigger(wildBody, 'surge', 900);
      shake(st, mood === 'waking', rm);
      if (mood === 'waking') flash(st, 'violet');
    } else if (mood === 'flickering') {
      retrigger(wildBody, 'flicker', 900);
    } else {
      burst(st, 'boop soft', W, 4, SPARK);
    }
    if (ev.wild) {
      u.disp.meter = after.meter;
      syncStage(ctx, st, before);
      floatText(st, W[0], g.wild.headY + 2, `${(ev.wild > 0) === (sign > 0) ? '+' : '−'}${Math.abs(ev.wild)} ${label}`, bad ? 'bad' : 'good');
    }
    if (ev.drain) {
      later(u, 320 * k, () => {
        projectile(st, 'lash', W, g.pet.head, '<i></i>', 300 * k, 4);
        later(u, 300 * k, () => {
          setPet(ctx, st, 'surprised');
          retrigger(petBody, 'hurt', 700);
          shake(st, false, rm);
          u.disp.energy = after.energy;
          syncStage(ctx, st, before);
          floatText(st, g.pet.head[0], g.pet.head[1] + 4, `${ev.drain} Energy`, 'bad');
        });
      });
    }
  });
  later(u, replyAt + (ev.drain ? 1500 : 1100) * k, () => {
    shot(st, 'wide');
    u.busy = false;
    u.disp = null;
    u.holdPet = false;
    u.holdWild = false;
    ctx.rerender();
  });
}

function finishChoreo(ctx, st, before, after) {
  const u = ctx.ui('encounter');
  const g = u.geom;
  const W = [g.wild.cx, g.wild.cy];
  setLog(ctx, after.log[after.log.length - 1]?.text || '', 'wild');
  u.disp.meter = after.meter;
  syncStage(ctx, st, before);
  setWild(st, after.creature.id, after.stateKey);
  st.classList.remove('hollow', 'phase2');
  st.classList.add('won');
  ctx.music('none');
  ctx.sfx('evolve_fanfare', 0.8);
  shot(st, 'wild');
  flash(st, 'gold');
  burst(st, 'spark big', W, 12, '<i></i>', 1400);
  retrigger(st.querySelector('.enc-wild'), 'joy', 1800);
  for (let i = 0; i < 6; i++) later(u, 300 + i * 160, () => vfx(st, 'rise heart', W[0] + (i - 2.5) * 5, W[1] - 6, HEART, 1500));
  later(u, 900, () => {
    setPet(ctx, st, 'excited');
    retrigger(st.querySelector('.enc-pet'), 'hop', 1200);
  });
  later(u, 1300, () => {
    u.busy = false;
    u.disp = null;
    u.holdPet = false;
    u.holdWild = false;
    u.phase = 'outro';
    ctx.rerender();
  });
}

function setLog(ctx, text, who) {
  const u = ctx.ui('encounter');
  u.log = { text, who };
  const p = document.querySelector('.enc-log .line');
  if (!p) return;
  p.innerHTML = logHTML(ctx, text);
  const card = p.closest('.enc-log');
  card.dataset.who = who;
  retrigger(card, 'pop', 400);
}

/** A log line with the names in bold, like the board. */
function logHTML(ctx, text) {
  const names = [ctx.d.trails?.encounter?.creature?.name, ctx.state.pet?.name].filter(Boolean);
  let s = esc(text || '');
  for (const n of names) s = s.split(esc(n)).join(`<b>${esc(n)}</b>`);
  return s;
}

// ------------------------------------------------------------------ the panel
function actionStyle(a, hollow) {
  if (a.kind === 'light') return hollow ? ['purify', 'purify'] : ['sun', 'sun'];
  return { physical: ['orange', 'nudge'], restore: ['teal', 'calm'], item: ['cream', 'bag'], companion: ['green', 'creature_petalune'] }[a.kind] || ['cream', a.icon];
}

function actionSub(a, v) {
  const L = v.meterLabel;
  if (a.kind === 'item') return v.items.length ? `${v.items.length} in your Bag` : 'Nothing useful yet';
  if (a.kind === 'restore') return '+30 Energy';
  if (a.kind === 'companion') return v.companionUsed ? 'Used this time' : `${v.goal === 'befriend' ? '+' : '−'}${a.power} ${L} · once`;
  return `${v.goal === 'befriend' ? '+' : '−'}${a.power} ${L}`;
}

function playPanel(ctx, v, u, hidden = false) {
  const hollow = v.creature.kind === 'hollow';
  const last = u.busy && u.log ? u.log : v.log[v.log.length - 1];
  return html`<div class="enc-panel ${hidden ? 'offstage' : ''} ${u.busy ? 'busy' : ''}" ${hidden ? raw('aria-hidden="true" inert') : ''}>
    <button class="enc-log" data-act="log" data-k="log" data-who="${last?.who || 'wild'}" aria-expanded="${u.logOpen ? 'true' : 'false'}" aria-live="polite">
      ${u.logOpen ? html`<ol class="hist">${v.log.slice(-6, -1).map((l) => html`<li class="${l.who}">${raw(logHTML(ctx, l.text))}</li>`)}</ol>` : ''}
      <p class="line">${raw(logHTML(ctx, last?.text))}</p>
      <span class="turn">Turn ${v.turn + 1}${v.phase2 ? ' · waking' : ''}</span>
      <span class="chev" aria-hidden="true"></span></button>
    <div class="enc-actions">
      ${v.actions.map((a) => {
        const [cls, ic] = actionStyle(a, hollow);
        const cost = a.energy > 0 ? a.energy : 0;
        return html`<button class="enc-act ${cls} ${a.kind}" data-act="do" data-arg="${a.id}" data-k="act-${a.id}" ${a.can && !u.busy && !v.done ? '' : raw('disabled')} aria-label="${a.name}: ${actionSub(a, v)}${cost ? `, costs ${cost} Energy` : ''}">
          <span class="ic"><img src="${icon(ic)}" alt=""></span>
          <span class="tx"><b>${a.name}</b><small>${actionSub(a, v)}${cost ? html`<span class="cost" title="Energy cost"><img src="${icon('energy')}" alt="">${cost}</span>` : ''}</small></span></button>`;
      })}
    </div>
    <button class="enc-retreat" data-act="retreat-confirm" data-k="retreat" ${u.busy || v.done ? raw('disabled') : ''}>${raw(RUNNER)}<span>Retreat</span></button>
  </div>`;
}

function cardPanel(ctx, v) {
  const C = v.creature;
  const pet = ctx.state.pet;
  const items = v.items;
  const rec = v.recommended.items.map((i) => ITEMS[i].name).join(', ');
  return html`<div class="enc-panel goal">
    <section class="enc-goal ${C.kind === 'hollow' ? 'hollow' : ''}">
      <div class="goal-kick"><img src="${icon(v.goal === 'befriend' ? 'calm' : 'purify')}" alt="">${v.goal === 'befriend' ? 'Befriend' : 'Restore'}</div>
      <h2>${C.boss ? C.name : `${C.name} appeared`}</h2>
      <p>${v.goal === 'befriend' ? raw(`Fill its <b>Calm</b> meter. Take turns using abilities, items or a quiet moment. ${esc(C.name)} may skitter, but nothing here can hurt ${esc(pet?.name || 'your Evochi')}.`)
        : raw(`Bring its <b>Instability</b> to zero. Lumen Glow works best on the Hollow. It may tire ${esc(pet?.name || 'your Evochi')} out, never worse.`)}</p>
      <div class="goal-recs"><span><img src="${itemImg(v.recommended.items[0])}" alt="">Recommended: <b>${rec}</b></span>
        <span class="muted">${items.length ? `You have ${items.slice(0, 3).map((i) => `${i.name}${i.qty > 1 ? ' ×' + i.qty : ''}`).join(', ')}` : 'No useful items yet (that’s fine)'}</span></div>
    </section>
    <button class="enc-cta" data-act="begin" data-autofocus data-k="begin"><span>Begin</span></button>
    <button class="enc-retreat" data-act="retreat-confirm" data-k="g-retreat">${raw(RUNNER)}<span>Not yet</span></button>
  </div>`;
}

function rewardTiles(r, C, goal, row = false) {
  const tiles = [];
  if (r.companion || goal === 'befriend') tiles.push({ img: icon('evodex'), name: 'EvoDex entry', sub: C.name });
  if (goal === 'restore') tiles.push({ img: icon('evodex'), name: 'Restored', sub: C.name });
  for (const id of r.items || []) tiles.push({ img: itemImg(id), name: ITEMS[id].name, sub: 'Keepsake' });
  if (r.coins) tiles.push({ img: icon('coin'), name: 'EvoCoins', sub: `×${r.coins}` });
  for (const [id, n] of Object.entries(r.gifts || {})) tiles.push({ img: itemImg(id), name: ITEMS[id].name, sub: `×${n}` });
  for (const t of r.titles || []) tiles.push({ img: icon('crown'), name: Q.TITLES[t].name, sub: 'Title' });
  return html`<div class="rw-grid ${row ? 'row' : ''}">${tiles.map((t) => html`<div class="rw-tile"><img src="${t.img}" alt=""><b>${t.name}</b><small>${t.sub}</small></div>`)}</div>`;
}

function resultPanel(ctx, v) {
  const C = v.creature;
  const r = Q.QUESTS[v.quest].rewards;
  const last = v.log[v.log.length - 1];
  const A = TR.AFFINITIES[C.affinity];
  return html`<div class="enc-panel result">
    <section class="rw-card"><h3>Rewards</h3>${rewardTiles(r, C, v.goal, true)}</section>
    <section class="dex-card ${v.goal}">
      <span class="pic"><img src="${icon('creature_' + C.id)}" alt=""></span>
      <div><b>${C.name} <img src="${icon(A.icon)}" alt="${A.name}"></b>
        <p>${v.goal === 'befriend' ? `New companion! ${C.name} joins your journey, visits your nest and helps in encounters.` : `${C.name} is restored. ${v.boss ? 'The third trail on the Waystone’s map glows again.' : 'The ruins feel brighter already.'}`}</p>
        <small>${v.turn} turn${v.turn === 1 ? '' : 's'}${Object.keys(v.used).length ? ' · ' + Object.entries(v.used).map(([id, n]) => `${ITEMS[id].name}${n > 1 ? ' ×' + n : ''}`).join(', ') : ''}</small></div>
    </section>
    <button class="enc-cta" data-act="finish" data-autofocus data-k="finish"><span>Continue</span>${raw('<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12h13M13 6l6 6-6 6" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"/></svg>')}</button>
  </div>`;
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
      : phase === 'card' ? cardPanel(ctx, v)
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
    const bottom = Math.max(0, ph - 20);
    if (view && view.style.bottom !== bottom + 'px') view.style.bottom = bottom + 'px';
    st.style.setProperty('--ph', `${bottom + 20}px`);
    syncStage(ctx, st, v);
    if (!st.dataset.init) {
      st.dataset.init = '1';
      if (u.phase === 'intro' && !u.introStarted) {
        u.introStarted = true;
        playIntro(ctx, st, v);
      } else {
        // a fresh stage mid-encounter (came back from elsewhere, or a reload): no intro, just the shot
        st.classList.add('pet-in', 'lit', 'eye-l', 'eye-r');
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
    const rib = st.querySelector('.enc-ribbon');
    const cap = st.querySelector('.enc-caption');
    if (rib && cap) {
      const on = u.phase === 'result';
      if (on && !rib.classList.contains('show')) {
        rib.innerHTML = `<div class="rb"><b>${v.goal === 'befriend' ? 'Success!' : 'Restored!'}</b><span>${esc(v.goal === 'befriend' ? `${v.creature.name} trusts you!` : `${v.creature.name} remembers its light.`)}</span></div>`;
        rib.classList.add('show');
        cap.innerHTML = `<p>${logHTML(ctx, v.log[v.log.length - 1]?.text)}</p>`;
        cap.classList.add('show');
        shot(st, 'wild');
      } else if (!on) {
        rib.classList.remove('show');
        cap.classList.remove('show');
      }
    }
  },
  actions: {
    'skip-intro'(ctx) {
      skipIntro(ctx);
    },
    begin(ctx) {
      ctx.ui('encounter').phase = 'play';
      ctx.sfx('ui_tap', 0.4);
      ctx.rerender();
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
    return html`<main class="screen scroll paper prep2 ${C.kind}" aria-label="Encounter preparation">
      <header class="prep-head">
        <button class="pb" data-act="back" aria-label="Back" data-k="tback">${ICON.back}</button>
        <img class="pi" src="${icon(place.badge)}" alt="">
        <div class="pt"><h1>${place.name}</h1><p>${place.line}</p></div>
        <button class="pb map" data-act="place" aria-label="Look around ${place.name}" data-k="p-place"><img src="${icon('trail')}" alt=""></button>
      </header>
      <div class="prep-body">
        <div class="prep-banner"><img src="${url(sc.file)}" alt=""><span class="pb-creature"><img src="${icon('creature_' + C.id)}" alt=""></span></div>
        <section class="prep-quest">
          <div class="pq-head"><span class="pq-badge ${C.kind}"><img src="${icon(E.goal === 'befriend' ? 'calm' : 'purify')}" alt=""></span>
            <div><b>${v.title}</b><small>${goalLine}</small></div></div>
          <ul class="checks">
            ${v.phase === 'available' || v.phase === 'locked' ? checkRow(false, v.phase === 'locked' ? v.lock.text : `Accept the job from ${giver.name}`) : checkRow(true, `Job accepted from ${giver.name}`)}
            ${v.walk ? checkRow(!!walkDone, walkDone ? `Reach ${place.name}` : `Walk ${fmt(v.resolved)} steps to ${place.name} · ${fmt(v.walk.progress || 0)} so far`) : ''}
            ${needs.map((x) => checkRow(x.ok, `Bring ${x.need} × ${ITEMS[x.id].name} (${x.have}/${x.need})`))}
            ${opts.map((x) => checkRow(x.ok, `Bring ${ITEMS[x.id].name} for a better start`, true))}
            ${checkRow(!!v.completed, E.goal === 'befriend' ? `Gain ${C.name}’s trust` : `Bring its Instability to zero`)}
          </ul>
        </section>
        <h3 class="prep-h">Your team <button class="help" data-act="team-help" aria-label="About your team" data-k="team-help">?</button></h3>
        <div class="team-row">
          ${pet ? html`<div class="team-card me ${stageOk ? '' : 'warn'}"><span class="tb"><img src="${icon(TR.AFFINITIES.lumen.icon)}" alt=""></span>
            <img class="tp" data-sprite="${spriteAttr(pet.stage, pet.paletteId, 'happy', [], '', 90)}" src="${BLANK}" alt="">
            <b>${pet.name}</b><small>Lv. ${ctx.d.pet.level}</small><small>${TR.maxEnergy(ctx.state)} Energy</small></div>` : ''}
          ${comps.map((c) => html`<div class="team-card"><span class="tb"><img src="${icon(TR.AFFINITIES[c.affinity].icon)}" alt=""></span><img class="tp" src="${icon('creature_' + c.id)}" alt=""><b>${c.name}</b><small>${c.companion?.name || 'Companion'}</small></div>`)}
          ${!comps.length ? html`<div class="team-card ghost"><span class="tp q">?</span><b>Companion</b><small>Befriend one to help</small></div>` : ''}
        </div>
        ${!stageOk ? html`<p class="prep-note">A ${stageLabel(E.recommended.stage)} or older Evochi has more Energy for this one. You can still go.</p>` : ''}
        <h3 class="prep-h">Recommended item <span>(optional)</span></h3>
        <section class="rec-item">
          <span class="ri"><img src="${itemImg(recId)}" alt=""></span>
          <div class="grow"><b>${ITEMS[recId].name}</b><small>${fx ? `${E.goal === 'befriend' ? '+' : '−'}${fx.amount} ${E.goal === 'befriend' ? 'Calm' : 'Instability'}${fx.liked ? ` · ${C.name} loves it` : ''}` : ''}</small><small>You have: <b>${have}</b></small></div>
          ${!have && recSrc ? html`<button class="mini" data-act="home" data-arg="${recSrc.route === 'station' ? recSrc.station : 'garden'}" data-k="rec-make">${recSrc.verb}</button>`
            : recs.length > 1 ? html`<button class="mini" data-act="rec-next" data-k="rec-next">Change</button>` : ''}
        </section>
        <h3 class="prep-h">Possible rewards</h3>
        ${rewardTiles(v.rewards, C, E.goal)}
        <div class="prep-cta">
          ${ready ? html`<button class="enc-cta big" data-act="travel" data-k="travel">${raw(PEAKS)}<span>Prepare &amp; Enter</span></button>`
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

