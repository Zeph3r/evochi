// Layered villagers ("puppets"): floor shadow, body, head (one image per expression) with a blink
// overlay, and the arm with their prop. Idle / talk / listen loops come from the manifest
// (tools/art/village_npcs.py NPC_ANIM) and play with the Web Animations API. Idle keeps its phase
// across re-renders (the screen is rebuilt on every tap), so villagers never visibly restart.
import { url } from './assets.js';

const EPOCH = performance.now();
let blinkTimers = [];
let LOOK = 'lit';

/** 'lit' (rendered in each room's own light) or 'classic' (the original flat shading): a setting. */
export function setLook(l) {
  LOOK = l === 'classic' ? 'classic' : 'lit';
}
export function getLook() {
  return LOOK;
}

const pct = (v, d) => `${((v / d) * 100).toFixed(3)}%`;

function boxStyle(b, W, H) {
  return `left:${pct(b[0], W)};top:${pct(b[1], H)};width:${pct(b[2] - b[0], W)};height:${pct(b[3] - b[1], H)}`;
}

/** Flattened sprite for an expression in the chosen look (cards, tabs, cameo). */
export function flatSprite(n, expr = 'neutral', look = LOOK) {
  const set = (look === 'classic' && n.exprClassic) || n.expr;
  return url(set[expr] || set.neutral);
}

/** Inner HTML of a villager button: shadow + puppet (or the flat sprite if the art has no layers). */
export function puppetHTML(n, { key, expr = 'neutral', look = LOOK, state = 'idle' } = {}) {
  if (!n.layers) return `<img class="flat" alt="" src="${flatSprite(n, expr, look)}">`;
  const W = n.w;
  const H = n.h;
  let shadow = '';
  const parts = n.layers.map((L) => {
    if (L.part === 'shadow') {
      shadow = `<img class="shadow" alt="" src="${url(L.file)}" style="${boxStyle(L.box, W, H)}">`;
      return '';
    }
    const set = L[look] || L.lit;
    const src = L.part === 'head' ? set[expr] || set.neutral : set;
    const origin = L.pivot ? `transform-origin:${pct(L.pivot[0], W)} ${pct(L.pivot[1], H)}` : '';
    let blink = '';
    if (L.part === 'head' && L.blink && expr !== 'happy') {
      const b = L.blink[look] || L.blink.lit;
      blink = `<img class="blink" alt="" src="${url(b.file)}" style="${boxStyle(b.box, W, H)}">`;
    }
    return `<div class="lyr" data-part="${L.part}" style="${origin}"><img alt="" src="${url(src)}" style="${boxStyle(L.box, W, H)}">${blink}</div>`;
  }).join('');
  const g = n.ground;
  return `${shadow}<div class="pup" data-npc="${key}" data-state="${state}" style="transform-origin:${pct(g[0], W)} ${pct(g[1], H)}">${parts}</div>`;
}

function frames(part, keys) {
  return keys.map((k) => (part === 'all'
    ? { offset: k[0], easing: 'ease-in-out', transform: `translateY(${(k[2] * 100).toFixed(2)}%) scale(${(2 - k[1]).toFixed(4)}, ${k[1]})` }
    : { offset: k[0], easing: 'ease-in-out', transform: `translate(${(k[2] * 100).toFixed(2)}%, ${(k[3] * 100).toFixed(2)}%) rotate(${k[1]}deg)` }));
}

/** (Re)start one puppet's loop. Idle resumes from the shared clock; talk/listen start fresh (a reaction). */
export function setPuppetState(pup, n, state) {
  if (!pup || !n?.anim) return;
  pup.dataset.state = state;
  const spec = n.anim[state] || n.anim.idle;
  if (!spec) return;
  const t = state === 'idle' ? (performance.now() - EPOCH) % spec.dur : 0;
  for (const el of [pup, ...pup.querySelectorAll('.lyr')]) el.getAnimations().forEach((a) => a.cancel());
  for (const [part, keys] of Object.entries(spec.tracks)) {
    const el = part === 'all' ? pup : pup.querySelector(`.lyr[data-part="${part}"]`);
    if (!el || !el.animate) continue;
    const a = el.animate(frames(part, keys), { duration: spec.dur, iterations: Infinity });
    a.currentTime = t;
  }
}

/** Start every puppet under root; `npcs(key)` returns the manifest entry. Call after each render. */
export function startPuppets(root, npcs, { reduced = false } = {}) {
  blinkTimers.forEach(clearTimeout);
  blinkTimers = [];
  if (reduced) return;
  for (const pup of root.querySelectorAll('.pup[data-npc]')) {
    const n = npcs(pup.dataset.npc);
    setPuppetState(pup, n, pup.dataset.state || 'idle');
    const b = pup.querySelector('.blink');
    if (!b) continue;
    const loop = (first) => {
      const id = setTimeout(() => {
        if (!b.isConnected) return;
        b.animate([{ opacity: 0 }, { opacity: 1, offset: 0.2 }, { opacity: 1, offset: 0.8 }, { opacity: 0 }], { duration: 170 });
        loop(false);
      }, (first ? 900 : 2400) + Math.random() * 3000);
      blinkTimers.push(id);
    };
    loop(true);
  }
}
