// Home Tales: the Home Map, the Garden, the Cottage, its Kitchen and Apothecary, and the Skills chart.
// No sixth tab: the Home Map opens from Home ("Explore Home"); Skills also live in Journey > Skills and
// the Cottage. Everything reuses the item catalog, story quests, reward grants and the account's home state.
import * as G from '../game/state.js';
import * as Q from '../game/story.js';
import * as H from '../game/home.js';
import { ITEMS } from '../game/catalog.js';
import { html, raw, fmt, duration } from '../ui/dom.js';
import { icon, itemImg, url, manifest, spriteAttr, BLANK } from '../ui/assets.js';
import { ICON } from '../ui/icons.js';
import { coinPill } from '../core/app.js';
import { openStoryQuest, openStoryReward, nextText, statusTag, walkBar, npcSprite } from './village.js';
import { skipTime } from './settings.js';
import { clueGlint, discoveryActions, creatureImg } from './trails.js';
import * as TR from '../game/trails.js';

const HM = () => manifest().home;
const DROP = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.8C9 7 5.5 10.6 5.5 14.6a6.5 6.5 0 0 0 13 0C18.5 10.6 15 7 12 2.8z" fill="#5BAFE0" stroke="#24597E" stroke-width="1.6"/><path d="M9 14.6a3 3 0 0 0 2.4 3" stroke="#E4F4FF" stroke-width="1.8" stroke-linecap="round" fill="none"/></svg>';
const SPARK = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2l2.2 7.8L22 12l-7.8 2.2L12 22l-2.2-7.8L2 12l7.8-2.2z" fill="#FFE27A" stroke="#C8832C" stroke-width="1.2" stroke-linejoin="round"/></svg>';
const SKILL_HOW = {
  farming: 'Harvest crops in your Garden. Slower crops give more XP.',
  cooking: 'Cook in your Kitchen. A perfect result gives +50% XP.',
  alchemy: 'Brew in your Apothecary. A perfect result gives +50% XP.',
};
const COUNT = { farming: ['harvests', 'harvest'], cooking: ['cooked', 'dish'], alchemy: ['brewed', 'brew'] };

// ------------------------------------------------------------------ shared bits
function hud(ctx, title, short, act = 'back') {
  return html`<header class="hud vhud"><button class="back-btn" data-act="${act}" aria-label="Back" data-k="hback">${ICON.back}</button>
    <h1 class="place-title"><span class="full">${title}</span><span class="short" aria-hidden="true">${short}</span></h1>${coinPill(ctx)}</header>`;
}

function petImg(ctx, expr = 'happy', maxH = 180) {
  const p = ctx.state.pet;
  if (!p || ctx.d.pet?.dead) return '';
  return html`<img data-sprite="${spriteAttr(p.stage, p.paletteId, expr, Object.values(p.equipped || {}), '', maxH)}" src="${BLANK}" alt="">`;
}

function yieldText(y) {
  return Object.entries(y).map(([id, n]) => `${n} ${H.itemLabel(id, n)}`).join(', ');
}

function effectText(it) {
  const e = it.effect || {};
  if (e.growth) return 'Speeds up one garden bed by half its growing time';
  const bits = [];
  if (e.vitality) bits.push(`+${e.vitality} vitality`);
  if (e.recovery) bits.push('helps an unwell Evochi');
  if (e.treat) bits.push('a treat (Bond +1 once a day)');
  return bits.join(' · ');
}

/** Text for the items still missing from a recipe or hand-in. */
function missingText(needs) {
  return needs.map((x) => `${x.need - x.have} more ${H.itemLabel(x.id, x.need - x.have)}`).join(' and ');
}

/** Navigate to a home destination: garden | cottage | skills | kitchen | apothecary | village | nest. */
export function goHome(ctx, where, opts) {
  if (where === 'kitchen' || where === 'apothecary') ctx.app.go('station', { id: where }, opts);
  else if (where === 'nest') ctx.app.tab('home');
  else ctx.app.go(where, {}, opts);
}

export function skillStrip(ctx, skill) {
  const s = ctx.d.home.skills[skill];
  return html`<button class="card skill-strip" data-act="skills" data-arg="${skill}" data-k="ss-${skill}" aria-label="${s.name} level ${s.level}. Open Skills">
    <img src="${icon(s.icon)}" alt="">
    <div class="grow" style="min-width:0"><div class="row between" style="gap:6px"><b class="h-card">${s.name} <span class="lv-chip">Lv ${s.level}</span></b><span class="tiny muted">${s.maxed ? 'Max level' : `${fmt(s.into)} / ${fmt(s.need)} XP`}</span></div>
      <div class="bar skill" style="--sc:${s.color};margin-top:5px"><i style="width:${s.maxed ? 100 : (s.into / s.need) * 100}%"></i></div></div>
    <span class="chev" aria-hidden="true">&rsaquo;</span></button>`;
}

/** A quest summary row (face, title, what's next, progress) that opens the quest card. */
function questStrip(ctx, v, lead) {
  if (!v) return '';
  return html`<button class="card story-strip" data-act="quest" data-arg="${v.id}" data-k="qs-${v.id}">
    <img class="face" src="${npcSprite(Q.QUESTS[v.id].giver, v.next.kind === 'handin' ? 'happy' : 'neutral')}" alt="">
    <div class="grow" style="min-width:0;text-align:left"><div class="tiny muted">${lead || (v.line === 'side' ? 'Side story · optional' : 'Home Tales')}</div>
      <b class="h-card">${v.title}</b><div class="small" style="color:var(--ink-700)">${nextText(v)}</div>
      ${v.accepted && !v.completed ? html`<div style="margin-top:6px">${walkBar(v)}</div>` : ''}</div>
    <span class="chev" aria-hidden="true">&rsaquo;</span></button>`;
}

function homeQuest(ctx) {
  const st = ctx.d.story;
  const list = [...st.home, ...st.side];
  return list.find((v) => v.accepted && !v.completed && v.next.kind === 'handin')
    || st.home.find((v) => v.accepted && !v.completed) || st.home.find((v) => v.phase === 'available')
    || st.side.find((v) => v.accepted && !v.completed) || st.home.find((v) => v.phase === 'locked') || null;
}

const sharedActions = {
  ...discoveryActions,
  go(ctx, where) {
    ctx.sfx('ui_tap', 0.4);
    goHome(ctx, where);
  },
  quest(ctx, id) {
    openStoryQuest(ctx, id);
  },
  skills(ctx, skill) {
    if (skill) ctx.ui('skills').skill = skill;
    ctx.sfx('ui_tap', 0.4);
    ctx.go('skills');
  },
};

// ------------------------------------------------------------------ quick seed shop (modal)
/** Buy `n` of a stackable item in one go (each unit is its own idempotent purchase). */
export function buyMany(ctx, id, n, requestId) {
  return ctx.act((s, now) => {
    let st = s;
    const events = [];
    for (let i = 0; i < n; i++) {
      const r = G.purchase(st, id, `${requestId}:${i}`, now);
      if (r.error) return i ? { state: st, events, error: null, partial: i } : r;
      st = r.state;
      events.push(...r.events);
    }
    return { state: st, events, error: null };
  });
}

export function openSeedShop(ctx, seed, after) {
  const m = { n: 3, id: G.uid('seeds') };
  ctx.modal({
    center: true,
    label: `Buy ${ITEMS[seed].name}`,
    render: (c) => {
      const it = ITEMS[seed];
      const bal = c.d.balance;
      const can = (n) => bal >= it.price * n;
      if (!can(m.n)) m.n = [3, 1].find(can) || 1;
      return html`<div class="stack center">
        <img src="${itemImg(seed)}" alt="" width="96" height="96" style="margin:0 auto">
        <h2 class="h-sec">${it.name}</h2>
        <p class="small muted" style="margin:0">${it.desc}</p>
        <div class="qty-pick" role="radiogroup" aria-label="How many">${[1, 3, 5].map((n) => html`<button role="radio" aria-checked="${m.n === n}" data-act="sq-n" data-arg="${n}" ${can(n) ? '' : raw('disabled')}>x${n}<small><img src="${icon('coin')}" alt="">${fmt(it.price * n)}</small></button>`)}</div>
        <button class="btn green block" data-act="sq-buy" ${can(m.n) ? '' : raw('disabled')} data-autofocus><img src="${icon('coin')}" alt="" width="22" height="22"><span>Buy ${m.n} for ${fmt(it.price * m.n)}</span></button>
        ${!can(1) ? html`<p class="small" style="margin:0;color:var(--gold-900)">You need ${fmt(it.price - bal)} more EvoCoins. Journey quests pay out every day.</p>` : ''}
        <button class="btn cream block" data-act="modal-close">Not now</button></div>`;
    },
    actions: {
      'sq-n': (c, n) => {
        m.n = Number(n);
        c.app.renderModals();
      },
      'sq-buy': (c) => {
        const r = buyMany(c, seed, m.n, m.id);
        if (r.error) return;
        m.id = G.uid('seeds');
        c.closeModal();
        c.toast(`+${m.n} ${H.itemLabel(seed, m.n)}`, 'ok', 'item:' + seed);
        c.track('item_purchased', { item: seed, qty: m.n });
        after?.(c);
      },
    },
  });
}

// ------------------------------------------------------------------ Home Map
const MAP_PINS = [
  { id: 'garden', label: 'Garden' },
  { id: 'cottage', label: 'Cottage' },
  { id: 'gate', label: 'Village Gate' },
];

function mapPin(ctx, id) {
  const h = ctx.d.home;
  const st = ctx.d.story;
  if (id === 'garden') {
    if (h.ripe) return { mark: 'handin', sub: `${h.ripe} ready!` };
    if (h.emptyOpen) return { mark: h.counts.harvests || h.growing ? null : 'quest', sub: `${h.emptyOpen} empty bed${h.emptyOpen > 1 ? 's' : ''}` };
    return { sub: `${h.growing} growing` };
  }
  if (id === 'cottage') {
    if (st.cottageReady) return { mark: 'quest', sub: 'Ready to restore' };
    if (!h.kitchen) return { lock: 'Needs repair' };
    return { sub: h.apothecary ? 'Kitchen · Apothecary' : 'Kitchen' };
  }
  return { mark: st.turnIns.length ? 'handin' : st.offers.length ? 'quest' : null, sub: 'Sunlit Village' };
}

function welcomeGift(ctx) {
  const r = ctx.act(H.claimStarterSeeds);
  if (r.error || !r.events.length) return;
  ctx.sfx('reward_chime');
  ctx.modal({
    center: true,
    label: 'Welcome home',
    render: () => html`<div class="stack center">
      <div class="story-banner">Welcome home!</div>
      <img src="${icon('home_map')}" alt="" width="84" height="84" style="margin:0 auto">
      <p class="body" style="margin:0">Mira left a pouch of seeds by your nest. Plant them in your Garden: crops grow over time, and faster when you go for a walk.</p>
      <div class="row" style="justify-content:center;gap:8px;flex-wrap:wrap">${Object.entries(H.STARTER_SEEDS).map(([id, n]) => html`<span class="reward-chip story"><img src="${itemImg(id)}" alt=""><span>${n} × ${ITEMS[id].name}</span></span>`)}</div>
      <button class="btn green block" data-act="gift-plant" data-autofocus>Plant them</button>
      <button class="btn cream block" data-act="modal-close">Look around first</button></div>`,
    actions: {
      'gift-plant': (c) => {
        c.closeModal();
        c.go('garden');
      },
    },
  });
}

function miniBed(p) {
  if (!p.unlocked) return html`<i class="mb locked" aria-hidden="true"><img src="${icon('lock')}" alt=""></i>`;
  if (p.empty) return html`<i class="mb bare" aria-hidden="true"></i>`;
  return html`<i class="mb ${p.ripe ? 'ripe' : ''}" style="--p:${p.progress.toFixed(3)}" aria-hidden="true"><img src="${itemImg(p.crop)}" alt=""></i>`;
}

export const homemap = {
  id: 'homemap',
  scene: () => null,
  mount(ctx) {
    const u = ctx.ui('homemap');
    if (!ctx.d.home.starterSeeds && !u.gift) {
      u.gift = true;
      setTimeout(() => welcomeGift(ctx.app.ctx()), 380);
    }
  },
  render(ctx) {
    const M = HM().map;
    const A = M.anchors;
    const h = ctx.d.home;
    const st = ctx.d.story;
    const restored = st.flags.cottage_restored;
    const pos = (a) => `left:${((a[0] / M.w) * 100).toFixed(2)}%;top:${((a[1] / M.h) * 100).toFixed(2)}%`;
    const pinFor = { garden: A.garden, cottage: A.cottage, gate: A.gate };
    const p = ctx.state.pet;
    const hq = homeQuest(ctx);
    const readyDishes = h.kitchen ? H.RECIPE_ORDER.filter((r) => H.recipeView(ctx.state, r).ready).length : 0;
    const sub = h.ripe ? `${h.ripe} bed${h.ripe > 1 ? 's' : ''} ready to harvest` : h.growing ? `${h.growing} growing` : h.emptyOpen ? 'Beds are ready for seeds' : '';
    return html`<main class="screen scroll paper village homemap" aria-label="Your Home">
      ${hud(ctx, 'Your Home', 'Home')}
      <div class="village-map" style="aspect-ratio:${M.w} / ${M.h}">
        <img class="plate" src="${url(restored ? M.restored : M.ruined)}" alt="Your home: the nest in the meadow, the garden beds on the right, ${restored ? 'your restored cottage' : 'an old cottage with a broken roof'} up the path and the gate to Sunlit Village.">
        ${p && !ctx.d.pet?.dead ? html`<button class="map-pet" data-act="go" data-arg="nest" data-k="pin-nest" style="${pos(A.nest)}" aria-label="Back to ${p.name}'s nest">${petImg(ctx, 'happy', 150)}<span class="name-chip">Nest</span></button>` : ''}
        ${clueGlint(ctx, 'homemap')}
        ${ctx.d.trails?.companions.length ? html`<div class="map-friend" style="${pos([A.nest[0] + 150, A.nest[1] - 40])}" aria-label="${ctx.d.trails.companions[0].name} is visiting"><img src="${url(manifest().trails.creatures[ctx.d.trails.companions[0].id].states[TR.CREATURES[ctx.d.trails.companions[0].id].states.done])}" alt=""></div>` : ''}
        ${MAP_PINS.map((pp) => {
          const s = mapPin(ctx, pp.id);
          const where = pp.id === 'gate' ? 'village' : pp.id;
          return html`<button class="pin ${s.mark ? 'has-' + s.mark : ''} ${s.lock ? 'locked' : ''}" data-act="go" data-arg="${where}" data-k="pin-${pp.id}" style="${pos(pinFor[pp.id])}"
            aria-label="${pp.label}${s.sub ? ', ' + s.sub : ''}${s.lock ? ', ' + s.lock : ''}">
            ${s.mark ? html`<i class="pin-mark" aria-hidden="true">${s.mark === 'handin' ? raw(ICON.checkDark) : '!'}</i>` : ''}<span>${pp.label}</span>${s.lock ? html`<small><img src="${icon('lock')}" alt="">${s.lock}</small>` : s.sub ? html`<small>${s.sub}</small>` : ''}</button>`;
        })}
      </div>
      <div class="pad stack" style="gap:10px;margin-top:-14px;position:relative;z-index:3;padding-bottom:calc(20px + var(--safe-bottom))">
        ${hq ? questStrip(ctx, hq, hq.phase === 'locked' ? 'Coming up · Home Tales' : null) : ''}
        <h2 class="h-sec sec-head">Around your home</h2>
        <button class="card home-row" data-act="go" data-arg="garden" data-k="hr-garden">
          <img class="ico" src="${icon('skill_farming')}" alt="">
          <div class="grow" style="min-width:0;text-align:left"><b class="h-card">Garden</b><div class="small muted">${sub}</div></div>
          <span class="mini-beds">${h.plots.map(miniBed)}</span>
          <span class="chev" aria-hidden="true">&rsaquo;</span></button>
        <button class="card home-row" data-act="go" data-arg="cottage" data-k="hr-cottage">
          <img class="ico" src="${icon(restored ? 'skill_cooking' : 'home_map')}" alt="">
          <div class="grow" style="min-width:0;text-align:left"><b class="h-card">Cottage</b>
            <div class="small muted">${restored ? (readyDishes ? `${readyDishes} recipe${readyDishes > 1 ? 's' : ''} ready to make` : h.apothecary ? 'Kitchen and Apothecary' : 'Kitchen open') : st.cottageReady ? 'Ready to restore!' : 'Needs a new roof'}</div></div>
          ${st.cottageReady ? html`<span class="tag ok">Ready</span>` : ''}
          <span class="chev" aria-hidden="true">&rsaquo;</span></button>
        <button class="card home-row skills-row" data-act="skills" data-k="hr-skills">
          <div class="grow" style="min-width:0;text-align:left"><b class="h-card">Skills</b>
            <div class="skill-chips">${H.SKILL_ORDER.map((k) => {
              const s = h.skills[k];
              return html`<span class="skill-chip" style="--sc:${s.color}"><img src="${icon(s.icon)}" alt=""><span>${s.name}</span><b>${s.level}</b></span>`;
            })}</div></div>
          <span class="chev" aria-hidden="true">&rsaquo;</span></button>
        <p class="small muted" style="margin:2px 4px">Walk → grow → cook and brew → share with your Evochi or a friend in the village. Nothing here ever expires.</p>
      </div>
    </main>`;
  },
  actions: { ...sharedActions },
};

// ------------------------------------------------------------------ Garden
/** Bed rectangle and crop sprite placement (percent of the garden plate) from the art's anchors. */
function bedGeom(pid) {
  const Gd = HM().garden;
  const C = HM().crops;
  const a = Gd.anchors[pid];
  const l = Gd.anchors[pid + 'l'];
  const r = Gd.anchors[pid + 'r'];
  const bw = r[0] - l[0];
  const s = bw / C.bedW;
  const P = (x, W) => (x / W) * 100;
  return {
    bed: { left: P(l[0], Gd.w), top: P(a[1] - bw * 0.27, Gd.h), w: P(bw, Gd.w), h: P(bw * 0.52, Gd.h) },
    crop: { left: P(a[0] - C.ground[0] * s, Gd.w), top: P(a[1] - C.ground[1] * s, Gd.h), w: P(C.w * s, Gd.w), h: P(C.h * s, Gd.h) },
  };
}
const box = (b) => `left:${b.left.toFixed(2)}%;top:${b.top.toFixed(2)}%;width:${b.w.toFixed(2)}%;height:${b.h.toFixed(2)}%`;

function bedChip(p) {
  if (!p.unlocked) return html`<span class="bed-chip locked"><img src="${icon('lock')}" alt="">Farming Lv ${p.need}</span>`;
  if (p.empty) return html`<span class="bed-chip plant">${raw(ICON.plus.s.replace('<svg', '<svg width="14" height="14"'))}Plant</span>`;
  if (p.ripe) return html`<span class="bed-chip ripe">${raw(SPARK)}Harvest!</span>`;
  return html`<span class="bed-chip grow"><i class="pring" style="--p:${p.progress.toFixed(3)}"></i>${Math.floor(p.progress * 100)}%</span>`;
}

function growthParts(ctx, p) {
  const plot = ctx.state.home.plots[p.id];
  const g = H.plotGrowth(ctx.state, plot, ctx.now);
  let left = 1;
  const take = (v) => {
    const x = Math.max(0, Math.min(left, v));
    left -= x;
    return x;
  };
  const tonic = take(plot.tonic ? H.GROW.sproutTonic : 0);
  const water = take(plot.watered ? H.GROW.water : 0);
  const walk = take(g.walk);
  const time = take(g.time);
  return { time, walk, water, tonic, steps: g.steps };
}

function bedPanel(ctx, p, plots) {
  const n = H.PLOTS.findIndex((x) => x.id === p.id) + 1;
  const ripe = plots.filter((x) => x.ripe);
  const head = html`<div class="row between" style="gap:8px"><h2 class="h-card" style="margin:0">Bed ${n}${p.crop ? html` · ${H.CROPS[p.crop].name}` : ''}</h2>
    ${ripe.length > 1 ? html`<button class="btn sm green" data-act="harvest-all" data-k="harvest-all">${raw(SPARK)}<span>Harvest all (${ripe.length})</span></button>`
      : !p.empty && p.unlocked ? html`<span class="tag small ${p.ripe ? 'ok' : 'cream'}">${p.ripe ? 'Ripe' : p.stage === 'sprout' ? 'Sprouting' : 'Growing'}</span>` : ''}</div>`;
  if (!p.unlocked) {
    return html`<section class="card bed-panel" aria-live="polite">${head}
      <p class="body" style="margin:6px 0 0">This bed opens at <b>Farming Lv ${p.need}</b>. Every harvest earns Farming XP.</p></section>`;
  }
  if (p.empty) {
    const anySeed = H.CROP_ORDER.some((c) => G.ownedQty(ctx.state, H.CROPS[c].seed) > 0);
    return html`<section class="card bed-panel" aria-live="polite">${head}
      <p class="small muted" style="margin:4px 0 8px">${anySeed ? 'Pick something to plant.' : 'No seeds left. Pick some up here or in the Market\'s Garden shelf.'}</p>
      <div class="seed-list">${H.CROP_ORDER.map((c) => {
        const C = H.CROPS[c];
        const have = G.ownedQty(ctx.state, C.seed);
        const open = H.cropUnlocked(ctx.state, c);
        return html`<div class="seed-row ${open ? '' : 'locked'}">
          <img src="${itemImg(C.seed)}" alt="">
          <div class="grow" style="min-width:0"><div class="row" style="gap:6px"><b class="nm">${C.name}</b>${have ? html`<span class="tag small cream">x${have}</span>` : ''}</div>
            <div class="tiny muted">${duration(C.growMin * 60000)} · ${yieldText(C.yield)} · +${C.xp} XP</div></div>
          ${!open ? html`<span class="tag small neutral"><img src="${icon('lock')}" alt="">Lv ${C.level}</span>`
            : have ? html`<button class="btn sm green" data-act="plant" data-arg="${p.id}:${c}" data-k="plant-${c}" aria-label="Plant ${C.name}">Plant</button>`
            : html`<button class="btn sm cream" data-act="buy-seed" data-arg="${C.seed}" data-k="buy-${c}" aria-label="Buy ${ITEMS[C.seed].name}"><img src="${icon('coin')}" alt="" width="18" height="18">${ITEMS[C.seed].price}</button>`}
        </div>`;
      })}</div></section>`;
  }
  const C = H.CROPS[p.crop];
  if (p.ripe) {
    return html`<section class="card bed-panel" aria-live="polite">${head}
      <div class="row" style="gap:10px;margin-top:8px"><img src="${itemImg(p.crop)}" alt="" width="56" height="56">
        <div class="grow"><b class="h-card">Ready to harvest!</b><div class="small muted">${yieldText(C.yield)} · +${C.xp} Farming XP</div></div></div>
      <button class="btn green block" style="margin-top:10px" data-act="harvest" data-arg="${p.id}" data-k="harvest-${p.id}">${raw(SPARK)}<span>Harvest</span></button></section>`;
  }
  const g = growthParts(ctx, p);
  const tonics = G.ownedQty(ctx.state, 'sprout_tonic');
  return html`<section class="card bed-panel" aria-live="polite">${head}
    <div class="grow-bar" role="progressbar" aria-label="Growth" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${Math.floor(p.progress * 100)}">
      <i class="t" style="width:${g.time * 100}%"></i><i class="w" style="width:${g.walk * 100}%"></i><i class="d" style="width:${g.water * 100}%"></i><i class="x" style="width:${g.tonic * 100}%"></i></div>
    <div class="row between" style="margin-top:6px;gap:6px"><b class="small">${Math.floor(p.progress * 100)}% grown</b>
      <span class="small" style="color:var(--ink-700)">Ready in ${duration(p.msLeft)}${p.stepsToRipe ? html`, or walk ${fmt(p.stepsToRipe)} steps` : ''}</span></div>
    <div class="grow-key"><span><i class="t"></i>Time</span><span><i class="w"></i>Walking ${g.steps ? `(${fmt(g.steps)} steps)` : ''}</span>${p.watered ? html`<span><i class="d"></i>Watered</span>` : ''}${p.tonic ? html`<span><i class="x"></i>Sprout Tonic</span>` : ''}</div>
    <div class="row" style="gap:8px;margin-top:10px;flex-wrap:wrap">
      <button class="btn sm ${p.watered ? 'cream' : ''}" data-act="water" data-arg="${p.id}" ${p.watered ? raw('disabled') : ''} data-k="water-${p.id}">${raw(DROP)}<span>${p.watered ? 'Watered' : 'Water +15%'}</span></button>
      ${tonics && !p.tonic ? html`<button class="btn sm cream" data-act="tonic" data-arg="${p.id}" data-k="tonic-${p.id}"><img src="${itemImg('sprout_tonic')}" alt="" width="24" height="24"><span>Sprout Tonic +50%</span></button>` : ''}
      <button class="btn sm green" data-act="walk" data-k="g-walk"><img src="${icon('steps')}" alt="" width="22" height="22"><span>Walk</span></button>
    </div></section>`;
}

function harvestPlot(ctx, pid) {
  const r = ctx.act(H.harvest, pid);
  if (r.error) return null;
  const ev = r.events.find((e) => e.type === 'harvested');
  const u = ctx.ui('garden');
  u.pops = { ...(u.pops || {}), [pid]: { items: ev.items, t: Date.now() } };
  setTimeout(() => {
    if (u.pops?.[pid] && Date.now() - u.pops[pid].t >= 1200) delete u.pops[pid];
    ctx.rerender();
  }, 1300);
  ctx.sfx('coin', 0.6);
  return ev;
}

export const garden = {
  id: 'garden',
  scene: () => null,
  render(ctx) {
    const Gd = HM().garden;
    const C = HM().crops;
    const u = ctx.ui('garden');
    const plots = H.PLOTS.map((x) => H.plotView(ctx.state, x.id, ctx.now));
    if (!plots.some((x) => x.id === u.sel)) u.sel = (plots.find((x) => x.ripe) || plots.find((x) => x.empty && x.unlocked) || plots[0]).id;
    const sel = plots.find((x) => x.id === u.sel);
    const geo = Object.fromEntries(plots.map((x) => [x.id, bedGeom(x.id)]));
    return html`<main class="screen scroll paper village garden" aria-label="Your Garden">
      ${hud(ctx, 'Your Garden', 'Garden')}
      <div class="garden-clip" style="aspect-ratio:${Gd.w} / ${Math.round(Gd.h * 0.86)}"><div class="garden-plate" style="aspect-ratio:${Gd.w} / ${Gd.h}">
        <img class="plate" src="${url(Gd.file)}" alt="Your garden: four raised beds inside a little fence.">
        ${plots.map((x) => (x.empty ? '' : html`<img class="crop ${x.ripe ? 'ripe' : ''} ${u.planted === x.id ? 'pop' : ''}" src="${url(C.files[x.crop][x.stage])}" alt="" style="${box(geo[x.id].crop)}">`))}
        ${plots.map((x) => {
          const pop = u.pops?.[x.id];
          return html`<button class="bed ${x.id === u.sel ? 'sel' : ''} ${x.ripe ? 'ripe' : ''} ${x.unlocked ? '' : 'locked'} ${u.splash === x.id ? 'splash' : ''}" data-act="bed" data-arg="${x.id}" data-k="bed-${x.id}" style="${box(geo[x.id].bed)}"
            aria-label="Bed ${H.PLOTS.findIndex((y) => y.id === x.id) + 1}: ${!x.unlocked ? `locked until Farming level ${x.need}` : x.empty ? 'empty' : x.ripe ? `${H.CROPS[x.crop].name}, ripe, tap to harvest` : `${H.CROPS[x.crop].name}, ${Math.floor(x.progress * 100)}% grown`}" aria-pressed="${x.id === u.sel}">
            ${bedChip(x)}
            ${pop ? html`<span class="pop-items" aria-hidden="true">${Object.entries(pop.items).map(([id, n]) => html`<span><img src="${itemImg(id)}" alt="">+${n}</span>`)}</span>` : ''}
          </button>`;
        })}
        ${clueGlint(ctx, 'garden')}
      </div></div>
      <div class="pad stack" style="gap:10px;margin-top:-16px;position:relative;z-index:3;padding-bottom:calc(20px + var(--safe-bottom))">
        ${bedPanel(ctx, sel, plots)}
        ${ctx.state.steps.connection === 'demo' && plots.some((x) => !x.empty && !x.ripe) ? html`<div class="card dev row" style="padding:8px 10px;gap:8px"><span class="tiny grow" style="font-weight:800;color:var(--ink-700)">Playtest: let time pass</span>
          <button class="btn sm cream" data-act="dev-skip" data-arg="10" data-k="g-skip10">+10 min</button><button class="btn sm cream" data-act="dev-skip" data-arg="60" data-k="g-skip60">+1 hour</button></div>` : ''}
        ${skillStrip(ctx, 'farming')}
        <p class="small muted" style="margin:2px 4px">Crops grow on their own. Steps you walk after planting speed them up (every 1,000 steps adds 10%, up to 60%), and watering adds 15%.</p>
      </div>
    </main>`;
  },
  actions: {
    ...sharedActions,
    bed(ctx, pid) {
      const u = ctx.ui('garden');
      const p = H.plotView(ctx.state, pid, ctx.now);
      if (p.ripe) {
        // one tap harvests a ripe bed
        u.sel = pid;
        harvestPlot(ctx, pid);
        return;
      }
      u.sel = pid;
      ctx.sfx('ui_tap', 0.4);
      ctx.rerender();
    },
    plant(ctx, arg) {
      const [pid, crop] = arg.split(':');
      const r = ctx.act(H.plant, pid, crop);
      if (r.error) return;
      const u = ctx.ui('garden');
      u.planted = pid;
      ctx.sfx('pet_chirp', 0.5);
      ctx.track('crop_planted', { crop });
      setTimeout(() => {
        if (u.planted === pid) u.planted = null;
      }, 700);
    },
    water(ctx, pid) {
      const r = ctx.act(H.water, pid);
      if (r.error) return;
      const u = ctx.ui('garden');
      u.splash = pid;
      ctx.sfx('ui_tap', 0.6);
      setTimeout(() => {
        u.splash = null;
        ctx.rerender();
      }, 900);
    },
    tonic(ctx, pid) {
      const r = ctx.act(H.useSproutTonic, pid);
      if (!r.error) ctx.sfx('reward_chime', 0.5);
    },
    harvest(ctx, pid) {
      harvestPlot(ctx, pid);
    },
    'harvest-all'(ctx) {
      for (const x of H.PLOTS) if (H.plotView(ctx.state, x.id, ctx.now).ripe) harvestPlot(ctx, x.id);
    },
    'buy-seed'(ctx, seed) {
      openSeedShop(ctx, seed);
    },
    'dev-skip'(ctx, min) {
      skipTime(ctx.store, Number(min) * 60000);
      ctx.sfx('ui_tap', 0.4);
    },
    walk(ctx) {
      ctx.app.ui.journey = { ...(ctx.app.ui.journey || {}), tab: 'daily' };
      ctx.app.tab('journey');
    },
  },
};

// ------------------------------------------------------------------ Cottage
/** The cottage close-up (ruined and restored renders, cross-faded while it's restored). */
function cottageView(ctx, showRestored, anim) {
  // older asset packs have no close-up: fall back to the Home Map, framed on the cottage
  const M = HM().map;
  const C = HM().cottage?.ruined ? HM().cottage : { ruined: M.ruined, restored: M.restored, w: 145, h: 100, fit: 'object-position:12% 16%' };
  return html`<div class="cottage-view ${anim ? 'restoring' : ''}" style="aspect-ratio:${C.w} / ${C.h};${C.fit ? '--cv-pos:12% 16%' : ''}">
    <img class="cv ruined" src="${url(C.ruined)}" alt="${showRestored ? '' : 'The old cottage: a broken roof, boarded windows and an empty doorway.'}">
    <img class="cv restored ${showRestored ? 'on' : ''}" src="${url(C.restored)}" alt="${showRestored ? 'Your restored cottage: a new red roof, warm windows and a puffing chimney.' : ''}">
    ${anim ? html`<span class="sparks" aria-hidden="true">${[30, 16, 42, 22, 36, 26].map((t, i) => html`<i style="--i:${i};left:${16 + i * 12}%;top:${t}%">${raw(SPARK)}</i>`)}</span>` : ''}
    ${showRestored ? clueGlint(ctx, 'cottage') : ''}
  </div>`;
}

function roomCard(ctx, id) {
  const S = H.STATIONS[id];
  const room = HM().rooms[id];
  const open = H.stationOpen(ctx.state, id);
  const sk = ctx.d.home.skills[S.skill];
  const v = Q.questView(ctx.state, S.quest, ctx.now);
  const ready = open ? H.RECIPE_ORDER.filter((r) => H.RECIPES[r].station === id && H.recipeView(ctx.state, r).ready).length : 0;
  return html`<button class="room-card ${open ? '' : 'locked'}" data-act="${open ? 'go' : 'quest'}" data-arg="${open ? id : S.quest}" data-k="room-${id}">
    <img class="thumb" src="${url(room.file)}" alt="">
    <span class="nm"><img src="${icon(H.SKILLS[S.skill].icon)}" alt="">${S.name}${open ? html`<span class="lv-chip">Lv ${sk.level}</span>` : ''}</span>
    <span class="ds">${open ? (ready ? `${ready} recipe${ready > 1 ? 's' : ''} ready` : id === 'kitchen' ? 'Meals and treats' : 'Tonics and teas') : v.completed ? 'Opening soon' : nextText(v)}</span>
    ${!open ? html`<span class="lock-badge"><img src="${icon('lock')}" alt=""></span>` : ready ? html`<i class="badge-dot" aria-hidden="true"></i>` : ''}
  </button>`;
}

export const cottage = {
  id: 'cottage',
  scene: () => null,
  render(ctx) {
    const st = ctx.d.story;
    const u = ctx.ui('cottage');
    if (u.route !== ctx.app.route) {
      // a fresh visit never resumes a half-watched restoration scene
      u.route = ctx.app.route;
      if (!u.anim) u.step = null;
    }
    const restored = st.flags.cottage_restored;
    const v = Q.questView(ctx.state, 'hq01', ctx.now);
    // the restoration plays out as a tiny scene: restore -> narration -> Bram -> reward
    const scene = u.step && Q.LINES[u.step] ? u.step : null;
    const showRestored = restored && (!scene || u.step !== 'HQ01_C00');
    let body;
    if (scene) {
      const L = Q.LINES[scene];
      const bram = L.s === 'npc_bram';
      body = html`<section class="card narration ${bram ? 'bram' : ''}" aria-live="polite">
        ${bram ? html`<img class="face" src="${npcSprite('npc_bram', L.e || 'happy')}" alt="">` : ''}
        <div class="grow">${bram ? html`<span class="speaker" style="--sc:#8D5D3B">Bram</span>` : ''}<p class="line">${Q.lineText(ctx.state, scene, ctx.now, ctx.state.pet?.name)}</p></div></section>
        <button class="btn block" data-act="scene-next" data-k="scene-next" data-autofocus>${scene === 'HQ01_C01' ? 'Continue' : 'Step inside'}</button>`;
    } else if (!restored) {
      const ready = v.phase === 'restoration_ready';
      const n = v.next;
      const cta = ready ? html`<button class="btn green block" data-act="restore" data-k="restore">${raw(SPARK)}<span>Restore the Cottage</span></button>`
        : v.phase === 'available' ? html`<button class="btn block" data-act="talk-bram" data-k="talk-bram">Talk to Bram in his Workshop</button>`
        : n.kind === 'walk' ? html`<button class="btn green block" data-act="walk" data-k="c-walk">Go for a walk</button>`
        : n.kind === 'gather' ? html`<button class="btn green block" data-act="go" data-arg="garden" data-k="c-garden">Visit your Garden</button>`
        : n.kind === 'handin' ? html`<button class="btn block" data-act="talk-bram" data-k="talk-bram">Bring them to Bram</button>` : '';
      body = html`<section class="card narration" aria-live="polite"><p class="line">${Q.lineText(ctx.state, ready ? 'HQ01_C00' : 'HQ01_C02', ctx.now)}</p></section>
        <section class="card cottage-quest">
          <div class="row" style="gap:10px"><img class="face" src="${npcSprite('npc_bram', 'neutral')}" alt="">
            <div class="grow" style="min-width:0"><div class="tiny muted">Home Tales · Quest 01</div><b class="h-card">${v.title}</b>
              <div class="row" style="gap:6px;margin-top:3px;flex-wrap:wrap"><span class="tag small cream">Lv ${v.level}+</span>${statusTag(v)}</div></div>
            <button class="btn sm cream" data-act="quest" data-arg="hq01" data-k="c-q">Details</button></div>
          <div class="small" style="margin-top:8px;font-weight:800">${nextText(v)}</div>
          ${v.accepted ? html`<div style="margin-top:6px">${walkBar(v)}</div>` : ''}
        </section>
        ${cta}`;
    } else {
      body = html`<p class="small muted" style="margin:2px 4px 0">${Q.lineText(ctx.state, 'HQ01_B08', ctx.now)} <span style="white-space:nowrap">- Bram</span></p>
        <h2 class="h-sec sec-head">Rooms</h2>
        <div class="place-grid">${roomCard(ctx, 'kitchen')}${roomCard(ctx, 'apothecary')}</div>
        ${questStrip(ctx, [...st.home, ...st.side].find((x) => x.accepted && !x.completed) || st.home.find((x) => x.phase === 'available') || null)}
        <h2 class="h-sec sec-head">Skills</h2>
        ${H.SKILL_ORDER.map((k) => skillStrip(ctx, k))}`;
    }
    return html`<main class="screen scroll paper village cottage" aria-label="Your Cottage">
      ${hud(ctx, restored ? 'Your Cottage' : 'Old Cottage', 'Cottage')}
      ${cottageView(ctx, showRestored || u.anim, u.anim)}
      <div class="pad stack" style="gap:10px;margin-top:-14px;position:relative;z-index:3;padding-bottom:calc(20px + var(--safe-bottom))">${body}</div>
    </main>`;
  },
  actions: {
    ...sharedActions,
    'talk-bram'(ctx) {
      ctx.go('place', { id: 'workshop', npc: 'npc_bram' });
    },
    walk(ctx) {
      ctx.app.ui.journey = { ...(ctx.app.ui.journey || {}), tab: 'daily' };
      ctx.app.tab('journey');
    },
    restore(ctx) {
      const r = ctx.act(Q.storyHandIn, 'hq01', 'restore_cottage');
      if (r.error) return;
      const u = ctx.ui('cottage');
      u.anim = true;
      u.step = 'HQ01_C01';
      ctx.sfx('evolve_fanfare');
      ctx.track('cottage_restored', {});
      setTimeout(() => {
        u.anim = false;
        ctx.rerender();
      }, ctx.app.reducedMotion ? 10 : 1900);
    },
    'scene-next'(ctx) {
      const u = ctx.ui('cottage');
      if (u.step === 'HQ01_C01') {
        u.step = 'HQ01_B09';
        ctx.sfx('ui_tap', 0.4);
        ctx.rerender();
        return;
      }
      u.step = null;
      ctx.rerender();
      openStoryReward(ctx, 'hq01', { then: 'stay' });
    },
  },
};

// ------------------------------------------------------------------ Kitchen / Apothecary
function recipeCard(ctx, r, S) {
  const it = ITEMS[r.makes];
  const owned = G.ownedQty(ctx.state, r.makes);
  return html`<div class="card recipe ${r.known ? '' : 'locked'} ${r.ready ? 'ready' : ''}">
    <div class="pic"><img src="${itemImg(r.makes)}" alt=""></div>
    <div style="min-width:0">
      <div class="row" style="gap:6px;flex-wrap:wrap"><b class="h-card">${r.name}</b>${owned ? html`<span class="tag small cream">x${owned}</span>` : ''}</div>
      <div class="tiny muted">${effectText(it)}</div>
      <div class="needs">${Object.entries(r.have).map(([id, x]) => html`<span class="need ${x.have >= x.need ? 'ok' : 'short'}" aria-label="${ITEMS[id].name}: ${x.have} of ${x.need}"><img src="${itemImg(id)}" alt="">${Math.min(x.have, 99)}/${x.need}</span>`)}</div>
    </div>
    ${!r.known ? html`<span class="tag small neutral"><img src="${icon('lock')}" alt="">Lv ${r.level}</span>`
      : html`<button class="btn sm ${r.ready ? 'green' : 'cream'}" data-act="craft" data-arg="${r.id}" data-k="cr-${r.id}">${S.verb}</button>`}
  </div>`;
}

/** Who in the story is waiting for this item right now (to suggest "take it to..."). */
function questWanting(ctx, itemId) {
  return ctx.d.story.all.find((v) => v.accepted && !v.completed && v.objectives.some((o) => o.item === itemId && !o.done)) || null;
}

const MG = {
  kitchen: { prompt: 'Tap when the marker reaches the golden zone to bake a perfect batch.', stop: 'Take it out!', skip: 'Skip, just cook it' },
  apothecary: { prompt: 'Tap when the marker reaches the golden zone to brew a perfect batch.', stop: 'Stir now!', skip: 'Skip, just brew it' },
};

function doCraft(ctx, rid, quality) {
  const R = H.RECIPES[rid];
  const r = ctx.act(H.craft, rid, quality === 'perfect' ? 'perfect' : 'good');
  if (r.error) return;
  const ev = r.events.find((e) => e.type === 'crafted');
  const xp = r.events.find((e) => e.type === 'skill_xp');
  const u = ctx.ui('station');
  u.joy = Date.now();
  setTimeout(() => ctx.rerender(), 1300);
  ctx.track('recipe_crafted', { recipe: rid, quality: ev.quality });
  ctx.sfx(ev.quality === 'perfect' ? 'level_up' : 'purchase', 0.7);
  const id = R.makes;
  const it = ITEMS[id];
  const S = H.STATIONS[R.station];
  ctx.modal({
    center: true,
    label: `${it.name} ready`,
    render: (c) => {
      const want = questWanting(c, id);
      const again = H.recipeView(c.state, rid).ready;
      const pet = c.state.pet;
      const giveable = !it.effect?.growth && pet && !c.d.pet?.dead && G.ownedQty(c.state, id) > 0;
      return html`<div class="stack center">
        <div class="story-banner">${ev.quality === 'perfect' ? 'Perfect!' : R.station === 'kitchen' ? 'Fresh from the oven!' : 'Brewed!'}</div>
        <div class="reward-card"><img src="${itemImg(id)}" alt="" width="112" height="112"><b class="h-card">${ev.qty} × ${it.name}</b>
          <p class="small" style="margin:4px 0 0;color:var(--ink-700)">${effectText(it)}</p></div>
        <div class="row" style="justify-content:center;gap:8px;flex-wrap:wrap"><span class="tag ok" style="height:32px;font-size:14px"><img src="${icon(H.SKILLS[S.skill].icon)}" alt="" style="width:24px;height:24px">+${xp?.amount || 0} ${H.SKILLS[S.skill].name} XP</span></div>
        ${want ? html`<button class="btn block" data-act="cr-quest" data-arg="${want.id}">Take it to ${Q.NPCS[Q.QUESTS[want.id].turnIns[0].npc]?.name || 'the village'}</button>` : ''}
        ${it.effect?.growth ? html`<button class="btn ${want ? 'cream' : ''} block" data-act="cr-garden">Use it in the Garden</button>`
          : giveable ? html`<button class="btn ${want ? 'cream' : ''} block" data-act="cr-give" ${want ? '' : raw('data-autofocus')}><img src="${icon('heart')}" alt="" width="22" height="22"><span>Give one to ${pet.name}</span></button>` : ''}
        ${again ? html`<button class="btn cream block" data-act="cr-again">${S.verb} another</button>` : ''}
        <button class="btn cream block" data-act="modal-close">Done</button></div>`;
    },
    actions: {
      'cr-give': (c) => {
        const g = c.act(G.useConsumable, id);
        if (g.error) return;
        const used = g.events.find((e) => e.type === 'used');
        c.toast(`${c.state.pet.name} loved it!${used?.vitality ? ` +${used.vitality} vitality` : ''}`, 'ok', 'heart');
        c.ui('station').joy = Date.now();
        c.sfx('pet_chirp');
        c.closeModal();
      },
      'cr-again': (c) => {
        c.closeModal();
        c.ui('station').cook = { rid, station: R.station, phase: 'in', t0: Date.now() };
        c.rerender();
      },
      'cr-garden': (c) => {
        c.closeModal();
        c.go('garden');
      },
      'cr-quest': (c, qid) => {
        c.closeModal();
        const n = Q.nextStep(c.state, qid);
        if (n.place && Q.PLACES[n.place]) c.go('place', { id: n.place, npc: n.npc });
        else openStoryQuest(c, qid);
      },
    },
  });
}

// The station is the focal point: picking a recipe pushes the camera in on the oven (or the cauldron),
// the ingredients drop in, the timing game plays on a gauge over the fire, and the dish pops out before
// the reward card. Everything about the cook lives in u.cook so a fuller minigame can replace the gauge.
const STAGE = {
  kitchen: { fx: 0.256, fy: 0.49, wide: 1.15, close: 2.1, glow: '255,150,60', label: 'The oven' },
  apothecary: { fx: 0.333, fy: 0.47, wide: 1.15, close: 2.1, glow: '170,120,255', label: 'The cauldron' },
};
const AR = 1000 / 780; // the room plates' height / width
function frameVars(id, Z, pre) {
  const F = STAGE[id];
  const cl = (v, lo) => Math.min(0, Math.max(lo, v));
  const l = cl(50 - F.fx * Z * 100, 100 - Z * 100);
  const t = cl(50 - F.fy * Z * AR * 100, 100 - Z * AR * 100);
  return `--${pre}l:${l.toFixed(2)}%;--${pre}t:${t.toFixed(2)}%;--${pre}w:${(Z * 100).toFixed(1)}%`;
}
// where the station's mouth sits inside the close-up frame (box %), for the glow, the drops and the pop
function mouthAt(id) {
  const F = STAGE[id];
  const Z = F.close;
  const cl = (v, lo) => Math.min(0, Math.max(lo, v));
  const l = cl(50 - F.fx * Z * 100, 100 - Z * 100);
  const t = cl(50 - F.fy * Z * AR * 100, 100 - Z * AR * 100);
  return [l + F.fx * Z * 100, t + F.fy * Z * AR * 100];
}

function cookStage(ctx, id, room) {
  const u = ctx.ui('station');
  const c = u.cook;
  const R = H.RECIPES[c.rid];
  const it = ITEMS[R.makes];
  const [mx, my] = mouthAt(id);
  const drops = Object.entries(R.needs).flatMap(([iid, n]) => Array.from({ length: Math.min(n, 3) }, () => iid)).slice(0, 6);
  return html`<div class="cook-stage" data-keep="cook-${c.t0}" style="${raw(frameVars(id, STAGE[id].wide, 'w'))};${raw(frameVars(id, STAGE[id].close, 'c'))};--mx:${mx.toFixed(1)}%;--my:${my.toFixed(1)}%;--glow:${STAGE[id].glow}" aria-label="${STAGE[id].label}">
    <div class="st-img"><img src="${url(room.file)}" alt=""></div>
    <i class="st-glow" aria-hidden="true"></i>
    ${id === 'apothecary' ? html`<span class="st-bubbles" aria-hidden="true">${Array.from({ length: 7 }, (_, i) => html`<i style="--i:${i}"></i>`)}</span>` : html`<span class="st-embers" aria-hidden="true">${Array.from({ length: 7 }, (_, i) => html`<i style="--i:${i}"></i>`)}</span>`}
    <span class="st-drops" aria-hidden="true">${drops.map((iid, i) => html`<img src="${itemImg(iid)}" alt="" style="--i:${i};--sx:${((i % 2 ? 1 : -1) * (40 + 22 * i)).toFixed(0)}px">`)}</span>
    <span class="st-pop" aria-hidden="true"><img src="${itemImg(R.makes)}" alt="">${Array.from({ length: 10 }, (_, i) => html`<i style="--a:${i * 36}deg;--d:${70 + (i % 3) * 22}px"></i>`)}</span>
    <div class="st-gauge" aria-hidden="true"><div class="mg-meter"><i class="zone" style="left:62%;width:18%"></i><i class="marker" style="left:0%"></i></div></div>
    <div class="st-banner" role="status"></div>
    <div class="st-name"><img src="${itemImg(R.makes)}" alt=""><b>${it.name}</b></div>
  </div>`;
}

function cookControls(ctx, id) {
  const u = ctx.ui('station');
  const c = u.cook;
  const T = MG[id];
  const ready = c.phase === 'play';
  return html`<div class="cook-controls">
    <p class="small" style="margin:0;color:var(--ink-700)">${c.phase === 'in' ? (id === 'kitchen' ? 'Into the oven it goes...' : 'Into the cauldron it goes...') : T.prompt}</p>
    <button class="btn green lg block" data-act="cook-stop" data-k="mg-stop" ${ready ? '' : raw('disabled')}>${T.stop}</button>
    <div class="row" style="gap:8px"><button class="btn cream grow" data-act="cook-skip" data-k="mg-skip">${T.skip}</button><button class="btn ghost" data-act="cook-cancel" data-k="mg-back">Back</button></div>
    <p class="tiny muted" style="margin:0">Optional: skipping makes a normal batch. Ingredients are only used once it's done.</p>
  </div>`;
}

function finishCook(ctx, quality) {
  const u = ctx.ui('station');
  const c = u.cook;
  if (!c || c.phase === 'done') return;
  c.phase = 'done';
  const st = document.querySelector('.cook-stage');
  if (st) {
    st.classList.remove('play');
    st.classList.add('done', 'r-' + quality);
    const b = st.querySelector('.st-banner');
    if (b) b.textContent = quality === 'perfect' ? 'Perfect! Double batch' : quality === 'good' ? 'Nicely done!' : '';
  }
  for (const b of document.querySelectorAll('.cook-controls .btn')) b.disabled = true;
  if (quality !== 'skip') ctx.sfx(quality === 'perfect' ? 'reward_chime' : 'ui_tap', 0.6);
  const rid = c.rid;
  setTimeout(() => {
    if (u.cook !== c) return;
    u.cook = null;
    ctx.rerender();
    doCraft(ctx.app.ctx(), rid, quality);
  }, quality === 'skip' ? 450 : 1350);
}

export const station = {
  id: 'station',
  scene: () => null,
  render(ctx) {
    const id = H.STATIONS[ctx.app.route.params.id] ? ctx.app.route.params.id : 'kitchen';
    const S = H.STATIONS[id];
    const room = HM().rooms[id];
    const open = H.stationOpen(ctx.state, id);
    const u = ctx.ui('station');
    if (u.cook && (u.cook.station !== id || !H.RECIPES[u.cook.rid])) u.cook = null;
    if (u.cook) {
      // the stage and the header stay put across re-renders (data-keep), so the push-in and the gauge run uninterrupted
      return html`<main class="screen scroll paper village station st-${id} cooking" aria-label="Your ${S.name}" data-keep-root="station">
        ${raw(String(hud(ctx, `Your ${S.name}`, S.name)).replace('<header class="hud vhud"', '<header data-keep="hud" class="hud vhud"'))}
        ${cookStage(ctx, id, room)}
        <div class="pad stack" style="gap:10px;margin-top:12px;position:relative;z-index:3;padding-bottom:calc(20px + var(--safe-bottom))">${cookControls(ctx, id)}</div>
      </main>`;
    }
    const joy = u.joy && Date.now() - u.joy < 1200;
    const recipes = H.RECIPE_ORDER.filter((r) => H.RECIPES[r].station === id).map((r) => H.recipeView(ctx.state, r));
    const v = Q.questView(ctx.state, S.quest, ctx.now);
    return html`<main class="screen scroll paper village station st-${id}" aria-label="Your ${S.name}">
      ${hud(ctx, `Your ${S.name}`, S.name)}
      <div class="room-plate">
        <img class="plate" src="${url(room.file)}" alt="${id === 'kitchen' ? 'The cottage kitchen: a brick oven glowing, shelves of jars and a round rug.' : 'The apothecary: a bubbling cauldron, bottle shelves and a round window.'}">
        <div class="room-pet ${joy ? 'joy' : ''}">${petImg(ctx, joy ? 'excited' : 'happy', 200)}</div>
      </div>
      <div class="pad stack" style="gap:10px;margin-top:-18px;position:relative;z-index:3;padding-bottom:calc(20px + var(--safe-bottom))">
        ${open ? skillStrip(ctx, S.skill) : questStrip(ctx, v, `The ${S.name} opens with`)}
        <h2 class="h-sec sec-head">Recipes</h2>
        <div class="list">${recipes.map((r) => recipeCard(ctx, r, S))}</div>
        <p class="small muted" style="margin:2px 4px">${S.verb}ing has a quick timing game. It's optional: skip it any time. A perfect result makes a double batch, and ingredients are never wasted.</p>
      </div>
    </main>`;
  },
  mount(ctx, el) {
    const u = ctx.ui('station');
    const c = u.cook;
    const st = el?.querySelector('.cook-stage');
    if (!c || !st) return;
    if (!st.dataset.started) {
      st.dataset.started = '1';
      requestAnimationFrame(() => requestAnimationFrame(() => st.classList.add('close')));
      setTimeout(() => {
        if (u.cook !== c || c.phase !== 'in') return;
        c.phase = 'play';
        c.p0 = performance.now();
        st.classList.add('play');
        ctx.rerender();
      }, ctx.app.reducedMotion ? 300 : 1750);
    }
    if (c.phase === 'play' && !c.raf) {
      const period = ctx.app.reducedMotion ? 2600 : 1700;
      const tick = () => {
        const mk = document.querySelector('.cook-stage .marker');
        if (u.cook !== c || c.phase !== 'play' || !mk) {
          c.raf = null;
          return;
        }
        const x = ((performance.now() - c.p0) / period) % 1 * 2;
        c.p = x < 1 ? x : 2 - x;
        mk.style.left = (c.p * 100).toFixed(2) + '%';
        c.raf = requestAnimationFrame(tick);
      };
      c.raf = requestAnimationFrame(tick);
    }
  },
  actions: {
    ...sharedActions,
    'cook-stop'(ctx) {
      const c = ctx.ui('station').cook;
      if (!c || c.phase !== 'play') return;
      const ok = c.p >= 0.62 - 0.015 && c.p <= 0.8 + 0.015;
      finishCook(ctx, ok ? 'perfect' : 'good');
    },
    'cook-skip'(ctx) {
      finishCook(ctx, 'skip');
    },
    'cook-cancel'(ctx) {
      const u = ctx.ui('station');
      u.cook = null;
      ctx.sfx('ui_tap', 0.3);
      ctx.rerender();
    },
    craft(ctx, rid) {
      const r = H.recipeView(ctx.state, rid);
      if (!r.open) {
        ctx.toast(`Your ${H.STATIONS[r.station].name} isn't open yet`, 'warn', 'lock');
        return;
      }
      if (!r.known) {
        ctx.toast(`Reach ${H.SKILLS[r.skill].name} Lv ${r.level} to learn this recipe`, 'warn', 'lock');
        return;
      }
      if (!r.ready) {
        const miss = Object.entries(r.have).filter(([, x]) => x.have < x.need).map(([id, x]) => ({ id, ...x }));
        ctx.toast(`You need ${missingText(miss)}`, 'warn', 'item:' + miss[0].id);
        ctx.sfx('error_bonk', 0.4);
        return;
      }
      const u = ctx.ui('station');
      u.cook = { rid, station: H.RECIPES[rid].station, phase: 'in', t0: Date.now() };
      ctx.sfx('ui_tap', 0.5);
      ctx.app.root.querySelector('.screen.scroll')?.scrollTo?.(0, 0);
      ctx.rerender();
    },
  },
};

// ------------------------------------------------------------------ Skills chart
function storyReq(ctx, m) {
  if (m.kind === 'recipe') {
    const S = H.STATIONS[H.RECIPES[m.id].station];
    return { qid: S.quest, done: H.stationOpen(ctx.state, S.id), text: `${S.name}: ${Q.QUESTS[S.quest].title}` };
  }
  if (m.kind === 'quest') {
    const v = Q.questView(ctx.state, m.id, ctx.now);
    return { qid: m.id, done: v.completed, text: `Story: ${v.title}` };
  }
  return null;
}

const KIND = { crop: 'New crop', plot: 'New bed', recipe: 'Recipe', quest: 'Story' };

function msImg(m) {
  if (m.kind === 'crop' || m.kind === 'recipe') return itemImg(m.id);
  if (m.kind === 'plot') return icon('skill_farming');
  return npcSprite(Q.QUESTS[m.id].giver, 'happy');
}

export function skillsPanel(ctx) {
  const u = ctx.ui('skills');
  const k = H.SKILLS[u.skill] ? u.skill : 'farming';
  const all = ctx.d.home.skills;
  const s = all[k];
  const counts = ctx.d.home.counts;
  const station = k === 'cooking' ? 'kitchen' : k === 'alchemy' ? 'apothecary' : null;
  const stOpen = !station || H.stationOpen(ctx.state, station);
  let nextMarked = false;
  const rows = H.milestones(k).map((m) => {
    const reached = s.level >= m.level;
    const sr = storyReq(ctx, m);
    const done = reached && (!sr || sr.done);
    let cls = done ? 'done' : reached ? 'story' : 'future';
    if (!done && !nextMarked) {
      nextMarked = true;
      cls += ' next';
    }
    return html`<li class="ms ${cls}">
      <span class="ms-lv">Lv ${m.level}</span><span class="ms-dot" aria-hidden="true">${done ? raw(ICON.check) : ''}</span>
      <button class="ms-card" data-act="ms" data-arg="${m.kind}:${m.id}" data-k="ms-${m.kind}-${m.id}" aria-label="${KIND[m.kind]}: ${m.label}. ${done ? 'Unlocked' : 'Locked'}">
        <img src="${msImg(m)}" alt="">
        <div style="min-width:0;text-align:left"><div class="row" style="gap:6px;flex-wrap:wrap"><b class="nm">${m.label}</b><span class="tag small ${m.kind === 'quest' ? 'story-tag-sm' : 'cream'}">${KIND[m.kind]}</span></div>
          <div class="reqs"><span class="req ${reached ? 'ok' : ''}">${reached ? raw(ICON.checkDark) : html`<img src="${icon('lock')}" alt="">`}${s.name} Lv ${m.level}</span>
            ${sr ? html`<span class="req ${sr.done ? 'ok' : ''}">${sr.done ? raw(ICON.checkDark) : html`<img src="${icon('journey')}" alt="">`}${sr.text}</span>` : ''}</div></div>
      </button></li>`;
  });
  const sq = station ? Q.questView(ctx.state, H.STATIONS[station].quest, ctx.now) : null;
  return html`<div class="tabs skill-tabs" role="tablist" aria-label="Skills" style="grid-template-columns:repeat(3,minmax(0,1fr))">
      ${H.SKILL_ORDER.map((id) => html`<button class="tab" role="tab" aria-selected="${id === k}" data-act="skill-tab" data-arg="${id}" data-k="sk-${id}"><img src="${icon(all[id].icon)}" alt=""><span>${all[id].name}</span><b class="lv-chip">${all[id].level}</b></button>`)}
    </div>
    <section class="card skill-card" aria-label="${s.name}, level ${s.level}">
      <div class="row" style="gap:12px"><img src="${icon(s.icon)}" alt="" width="60" height="60">
        <div class="grow" style="min-width:0"><div class="row between"><b class="h-sec">${s.name}</b><span class="tag stage">Lv ${s.level}</span></div>
          <div class="bar skill" style="--sc:${s.color};margin-top:6px" role="progressbar" aria-label="${s.name} XP" aria-valuemin="0" aria-valuemax="${s.need}" aria-valuenow="${s.into}"><i style="width:${s.maxed ? 100 : (s.into / s.need) * 100}%"></i></div>
          <div class="tiny muted" style="margin-top:3px">${s.maxed ? 'Max level' : `${fmt(s.into)} / ${fmt(s.need)} XP to Lv ${s.level + 1}`} · ${fmt(counts[COUNT[k][0]])} ${COUNT[k][1]}${counts[COUNT[k][0]] === 1 ? '' : COUNT[k][1].endsWith('h') ? 'es' : 's'}</div></div></div>
      <p class="small" style="margin:8px 0 0;color:var(--ink-700)">${SKILL_HOW[k]}</p>
      ${!stOpen ? html`<button class="status-banner sync skill-lock" data-act="quest" data-arg="${sq.id}" data-k="sk-lock"><img src="${icon('lock')}" alt=""><span class="grow">Your ${H.STATIONS[station].name} opens with the story quest <b>${sq.title}</b>. ${nextText(sq)}</span><span class="chev" aria-hidden="true">&rsaquo;</span></button>` : ''}
    </section>
    <h2 class="h-sec sec-head">Milestones</h2>
    <ol class="ms-list">${rows}</ol>
    <p class="small muted" style="margin:2px 4px">Each milestone shows what it needs: a skill level, and sometimes a story quest. Side stories are always optional.</p>`;
}

export const skillsActions = {
  'skill-tab'(ctx, id) {
    ctx.ui('skills').skill = id;
    ctx.sfx('ui_tap', 0.3);
    ctx.rerender();
  },
  ms(ctx, arg) {
    const [kind, id] = arg.split(':');
    if (kind === 'quest') return openStoryQuest(ctx, id);
    if (kind === 'recipe') {
      const R = H.RECIPES[id];
      if (H.stationOpen(ctx.state, R.station)) return goHome(ctx, R.station);
      return openStoryQuest(ctx, H.STATIONS[R.station].quest);
    }
    goHome(ctx, 'garden');
  },
  quest(ctx, id) {
    openStoryQuest(ctx, id);
  },
};

export const skills = {
  id: 'skills',
  scene: () => null,
  render(ctx) {
    return html`<main class="screen scroll paper village skills" aria-label="Skills">
      ${hud(ctx, 'Skills', 'Skills')}
      <div class="pad stack" style="gap:10px;padding-top:6px;padding-bottom:calc(20px + var(--safe-bottom))">${skillsPanel(ctx)}</div>
    </main>`;
  },
  actions: { ...sharedActions, ...skillsActions },
};

