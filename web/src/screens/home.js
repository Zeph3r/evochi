// S06 Home / Nest (style guide §10, §14, §17).
import * as G from '../game/state.js';
import { CONFIG, PALETTES } from '../game/config.js';
import { ITEMS, DECOR_SLOTS } from '../game/catalog.js';
import { html, raw, fmt, timeAgo, duration } from '../ui/dom.js';
import { icon, itemImg, spriteAttr, BLANK } from '../ui/assets.js';
import { ICON } from '../ui/icons.js';
import { coinPill, nav, titleImg, stageLabel, statusTag } from '../core/app.js';
import { memorialView, memorialActions } from './pet.js';
import { openStoryQuest, nextText, npcSprite } from './village.js';
import { QUESTS } from '../game/story.js';
import { discoveryChip, discoveryActions } from './trails.js';

export function isNight(now, tz) {
  try {
    const h = Number(new Intl.DateTimeFormat('en-US', { hour: 'numeric', hourCycle: 'h23', timeZone: tz }).format(new Date(now)));
    return h >= 23 || h < 6;
  } catch {
    return false;
  }
}

// Sleep (style guide §20): the pet dozes in a quiet state - no touches for a while (sooner at night) -
// or when its bed is tapped. Any interaction wakes it.
const IDLE_SLEEP_MS = 45000;
const NIGHT_SLEEP_MS = 12000;
export function isSleeping(ctx) {
  const u = ctx.ui('home');
  const now = Date.now();
  if (u.wakeUntil && u.wakeUntil > now) return false;
  if (u.napUntil && u.napUntil > now) return true;
  const idle = now - (ctx.app.lastInput || now);
  return idle > (isNight(ctx.now, ctx.d.tz) ? NIGHT_SLEEP_MS : IDLE_SLEEP_MS);
}

export function petScene(ctx, extra = {}, { allowSleep = false } = {}) {
  const s = ctx.state;
  const p = s.pet;
  const d = ctx.d;
  const u = ctx.ui('home');
  const awake = !allowSleep || !isSleeping(ctx);
  return {
    habitat: 'meadow', decor: s.nest.placements, background: '#86C95B',
    focus: { x: 0.5, y: u.groundY || 0.4 },
    pet: {
      stage: p.stage, palette: p.paletteId, status: d.pet.status, equipped: Object.values(p.equipped || {}),
      sleeping: !awake && d.pet.status !== 'dead', label: `Pet ${p.name}`,
    },
    ...extra,
  };
}

export const home = {
  id: 'home',
  scene(ctx) {
    if (ctx.d.pet?.dead) return memorialView.scene(ctx);
    return petScene(ctx, {}, { allowSleep: true });
  },
  afterLayout(ctx, el) {
    if (ctx.d.pet?.dead) return memorialView.afterLayout?.(ctx, el);
    const stack = el.querySelector('.home-stack');
    const top = stack.getBoundingClientRect().top - ctx.app.root.getBoundingClientRect().top;
    const u = ctx.ui('home');
    const hud = el.querySelector('.hud').getBoundingClientRect().bottom - ctx.app.root.getBoundingClientRect().top;
    // the hero space (min 200px, style guide §23) always sits between the HUD and the cards
    u.groundY = Math.round(Math.max(hud + 120, top - 26));
    return home.scene(ctx);
  },
  position(ctx, el) {
    const b = el.querySelector('.evolve-cta');
    const pr = ctx.scene.petRect();
    if (b && pr) b.style.top = Math.max(110, pr.top - 14) + 'px';
    const bed = el.querySelector('.bed-zone');
    if (bed && pr && ctx.scene.ground) {
      const [gx, gy] = ctx.scene.ground;
      const w = pr.w * 0.95;
      Object.assign(bed.style, { left: gx - w / 2 + 'px', top: gy - 8 + 'px', width: w + 'px', height: '34px' });
    }
  },
  onPetTap(ctx) {
    home.actions.pet(ctx);
  },
  render(ctx) {
    const d = ctx.d;
    if (d.pet?.dead) return memorialView.render(ctx);
    const s = ctx.state;
    const p = s.pet;
    const dp = d.pet;
    const u = ctx.ui('home');
    const chip = storyChip(ctx);
    // the story chip takes the evolution strip's room, so the strip folds into its compact chip
    const compact = ctx.H < 650 || (chip && ctx.H < 920);
    const conn = s.steps.connection;
    const stepsPct = Math.min(1, d.todaySteps / d.goal);
    const banner = statusBanner(ctx);
    const showCoach = !s.flags.coachDone;
    const homeNew = !!(d.home && (d.home.ripe || !d.home.starterSeeds || d.story?.cottageReady || d.trails?.ready.some((x) => ['homemap', 'garden', 'cottage'].includes(x.place))));
    return html`<main class="screen" aria-label="Home">
      <header class="hud">
        <div>
          <h1 class="sr-only">Evochi - ${p.name}'s nest</h1>
          ${titleImg('wordmark_evochi', 'Evochi', 'wordmark')}
          <button class="loc-pill" data-act="habitat" data-k="loc" aria-label="Sunlit Meadow - arrange decorations"><img src="${icon('pin')}" alt="">Sunlit Meadow<span class="chev" aria-hidden="true">&rsaquo;</span></button>
          <div class="trip-row"><button class="village-btn home-btn" data-act="explore-home" data-k="explore" aria-label="Explore Home${homeNew ? ', something new' : ''}"><img src="${icon('home_map')}" alt="">Explore Home${homeNew ? raw('<i class="badge-dot" aria-hidden="true"></i>') : ''}</button>
            <button class="village-btn" data-act="visit-village" data-k="village" aria-label="Visit Sunlit Village${d.story?.attention ? ', something new' : ''}"><img src="${icon('habitats')}" alt=""><span class="vlong">Visit Village</span><span class="vshort" aria-hidden="true">Village</span>${d.story?.attention ? raw('<i class="badge-dot" aria-hidden="true"></i>') : ''}</button></div>
        </div>
        <div class="hud-col">
          ${coinPill(ctx)}
          <button class="sq-btn" data-act="settings" aria-label="Settings" data-k="set"><img src="${icon('settings')}" alt=""></button>
          <button class="sq-btn" data-act="mail" aria-label="Quests and rewards${d.claimable ? `, ${d.claimable} ready` : ''}" data-k="mail"><img src="${icon('mail')}" alt="">${d.claimable ? html`<i class="badge-dot">${d.claimable}</i>` : ''}</button>
        </div>
      </header>
      <button class="bed-zone" data-act="nap" data-k="bed" aria-label="${isSleeping(ctx) ? `Wake ${p.name}` : `Tuck ${p.name} into the nest for a nap`}"></button>
      ${dp.evo.eligible ? html`<button class="btn evolve-cta" data-act="evolve" data-k="evolve" style="top:140px"><img class="ico" src="${icon('evolve')}" alt=""><span>Evolve ${p.name}!</span></button>` : ''}
      <div class="spacer hero-space" aria-hidden="true"></div>
      <div class="home-stack">
        ${banner}
        ${chip}
        ${chip ? '' : discoveryChip(ctx)}
        <section class="card id-card" aria-label="${p.name}, level ${dp.level}">
          <div class="stack" style="gap:6px;min-width:0">
            <div class="row" style="gap:8px;min-width:0"><h2 class="pet-name">${p.name}</h2><button class="icon-btn" data-act="rename" aria-label="Rename ${p.name}" data-k="rename">${ICON.edit}</button></div>
            <div class="row" style="gap:6px;flex-wrap:wrap"><span class="tag stage">${stageLabel(p.stage)}</span>${statusTag(dp.status)}</div>
            ${evoNext(ctx)}
          </div>
          <div class="divider" aria-hidden="true"></div>
          <div class="stack" style="gap:5px;justify-content:center">
            <div class="lv">Lv. <b class="num">${dp.level}</b></div>
            <div class="xp-row"><div class="bar" role="progressbar" aria-label="Experience" aria-valuemin="0" aria-valuemax="${dp.need}" aria-valuenow="${dp.into}"><i style="width:${dp.need ? (dp.into / dp.need) * 100 : 100}%"></i></div><span class="small">${fmt(dp.into)} / ${fmt(dp.need)} XP</span></div>
            <div class="row between" style="gap:4px">
              <div class="hearts" aria-label="Bond ${dp.bond} of 100">${raw(hearts(dp.hearts))}</div>
              <span class="row" style="gap:4px;flex:none"><span class="small bond-lbl" style="font-family:var(--font-game);font-weight:800;color:var(--ink-500)">Bond</span><button class="help-btn" data-act="bond-help" aria-label="What is bond?" data-k="bondq">?</button></span>
            </div>
          </div>
        </section>
        <section class="card steps-card" aria-label="Daily steps">
          <div class="round-ico"><img src="${icon('steps')}" alt=""></div>
          <button class="grow" data-act="tab" data-arg="journey" style="all:unset;flex:1;min-width:0;cursor:pointer" aria-label="Daily steps ${fmt(d.todaySteps)} of ${fmt(d.goal)}. Open Journey" data-k="steps">
            <div class="small" style="font-weight:700;color:var(--ink-700)">Daily Steps ${d.todayUnverified ? html`<span class="tag small warn">Unverified</span>` : ''}</div>
            <div class="steps-num">${fmt(d.todaySteps)} <span>/ ${fmt(d.goal)} steps</span></div>
            <div class="bar green ${u.syncing ? 'sync' : ''}" aria-hidden="true"><i style="width:${stepsPct * 100}%"></i></div>
          </button>
          <div class="vsep" aria-hidden="true"></div>
          ${conn === 'none'
            ? html`<button class="btn sm green" data-act="connect" data-k="conn">Connect</button>`
            : html`<span class="xp-chip" aria-label="${dp.xpToday} XP earned today">${ICON.up}+${dp.xpToday} XP today!</span>`}
        </section>
        <div class="btn-row">
          <button class="btn stacked" data-act="pet" data-k="pet-btn"><img class="ico" src="${icon('heart')}" alt=""><span>Pet</span></button>
          <button class="btn green stacked" data-act="play" data-k="play-btn"><img class="ico" src="${icon('play')}" alt=""><span>Play</span></button>
          <button class="btn cream stacked" data-act="inspect" data-k="inspect-btn"><img class="ico" src="${icon('inspect')}" alt=""><span>Inspect</span></button>
        </div>
        ${compact ? evoChip(ctx) : evoFamily(ctx)}
      </div>
      ${nav(ctx, 'home')}
      ${showCoach ? coach(ctx) : ''}
    </main>`;
  },
  actions: {
    pet(ctx) {
      if (ctx.d.pet.dead) return;
      const u = ctx.ui('home');
      u.wakeUntil = Date.now() + 1500;
      u.napUntil = 0;
      ctx.act(G.interact, 'pet');
      ctx.scene.react('pet');
      ctx.sfx('pet_chirp');
      ctx.track('interact', { kind: 'pet' });
    },
    play(ctx) {
      if (ctx.d.pet.dead) return;
      const u = ctx.ui('home');
      u.wakeUntil = Date.now() + 1500;
      u.napUntil = 0;
      ctx.act(G.interact, 'play');
      ctx.scene.react('play');
      ctx.sfx('play_boing');
      ctx.track('interact', { kind: 'play' });
    },
    inspect(ctx) {
      ctx.scene.react('inspect');
      ctx.go('inspect');
    },
    evolve(ctx) {
      ctx.go('evolve');
    },
    connect(ctx) {
      ctx.go('settings', { focus: 'steps' });
    },
    rename(ctx) {
      const u = ctx.ui('rename');
      u.v = ctx.state.pet.name;
      u.err = null;
      ctx.modal({
        label: 'Rename',
        render: (c) => html`<div class="stack">
          <h2 class="h-sec">Rename your Evochi</h2>
          <input class="input" data-input="rn" value="${u.v}" maxlength="12" data-autofocus aria-label="New name">
          ${u.err ? html`<p class="field-err" role="alert">${u.err}</p>` : ''}
          <button class="btn block" data-act="rn-save">Save</button>
          <button class="btn cream block" data-act="modal-close">Cancel</button></div>`,
        inputs: { rn: (c, v) => (u.v = v) },
        actions: {
          'rn-save': (c) => {
            const r = G.renamePet(c.store.state, u.v);
            if (r.error) {
              u.err = r.message;
              c.app.renderModals();
              return;
            }
            c.store.replace(r.state);
            c.closeModal();
            c.scene.react('pet');
          },
        },
      });
    },
    nap(ctx) {
      const u = ctx.ui('home');
      if (isSleeping(ctx)) {
        u.napUntil = 0;
        u.wakeUntil = Date.now() + 1500;
        ctx.app.lastInput = Date.now();
        ctx.scene.react('surprised');
      } else {
        u.napUntil = Date.now() + 60000;
        u.wakeUntil = 0;
      }
      ctx.sfx('ui_tap', 0.4);
      ctx.rerender();
    },
    'bond-help'(ctx) {
      const b = CONFIG.bond;
      ctx.modal({
        label: 'Bond',
        render: (c) => html`<div class="stack">
          <div class="row"><img src="${icon('heart')}" alt="" width="40" height="40"><h2 class="h-sec">Bond ${c.d.pet.bond} / 100</h2></div>
          <p class="body">Bond is your friendship with ${c.state.pet.name}. It grows from your first pet (+${b.firstPet}) and first play (+${b.firstPlay}) each day, plus +${b.goalCelebration} when you reach your step goal. Direct interactions add at most +${b.directDailyCap} a day, so there's no need to tap-grind.</p>
          <p class="body muted">Higher bond unlocks more playful idle gestures. It never affects step access or health.</p>
          <button class="btn cream block" data-act="modal-close" data-autofocus>Got it</button></div>`,
      });
    },
    habitat(ctx) {
      openHabitatSheet(ctx);
    },
    care(ctx) {
      openCareSheet(ctx);
    },
    'coach-next'(ctx) {
      const u = ctx.ui('coach');
      u.i = (u.i || 0) + 1;
      if (u.i >= COACH.length) home.actions['coach-done'](ctx);
      else ctx.rerender();
    },
    'coach-done'(ctx) {
      const s = structuredClone(ctx.store.state);
      s.flags.coachDone = true;
      ctx.store.replace(s);
    },
    ...discoveryActions,
    'explore-home'(ctx) {
      ctx.sfx('ui_tap', 0.4);
      ctx.go('homemap');
    },
    'story-chip'(ctx, id) {
      openStoryQuest(ctx, id);
    },
    'goto-memorial'(ctx) {
      ctx.go('home');
    },
    ...memorialActions,
  },
};

// the tracked story quest, one compact row above the pet card (only while a walk or hand-in is pending)
function storyChip(ctx) {
  const v = ctx.d.story?.active;
  if (!v || !v.tracked || ctx.H < 640) return '';
  return html`<button class="card story-chip" data-act="story-chip" data-arg="${v.id}" data-k="story-chip">
    <img src="${npcSprite(QUESTS[v.id].giver, v.next.kind === 'handin' ? 'happy' : 'neutral')}" alt="">
    <div style="min-width:0"><div class="t">${v.title}</div><div class="d">${nextText(v)}</div></div></button>`;
}

function hearts(n) {
  let out = `<img class="first" src="${icon('heart')}" alt="">`;
  for (let i = 0; i < 5; i++) out += `<img src="${icon(i < n ? 'heart' : 'heart_empty')}" alt="">`;
  return out;
}

function statusBanner(ctx) {
  const d = ctx.d;
  const s = ctx.state;
  if (d.pet.status === 'sick') {
    return html`<div class="status-banner sick card" role="status"><img src="${icon('potion')}" alt=""><span class="grow">${s.pet.name} feels unwell. A walk or a Healing Herb will help.</span><button class="btn sm" data-act="care" data-k="care">Care</button></div>`;
  }
  if (s.steps.connection !== 'none' && s.steps.lastSync && ctx.now - s.steps.lastSync > 36 * 3600 * 1000) {
    return html`<div class="status-banner sync" role="status"><img src="${icon('steps')}" alt=""><span class="grow">Steps last synced ${timeAgo(s.steps.lastSync, ctx.now)}. Missing days count as pending, not inactive.</span></div>`;
  }
  return '';
}

function evoFamily(ctx) {
  const p = ctx.state.pet;
  return html`<section class="card evo-card" aria-label="Evolution family">
    <div class="row between"><h2 class="h-card sec-head" style="font-size:15px">Evolution Family</h2><span class="tiny muted">Grow together!</span></div>
    <div class="evo-strip">
      ${[1, 2, 3].map((st, i) => html`${i ? html`<div class="chev" aria-hidden="true">&rsaquo;</div>` : ''}
        <button class="evo-cell ${st === p.stage ? 'current' : ''}" data-act="inspect" aria-label="${stageLabel(st)}${st === p.stage ? ', current form' : st < p.stage ? ', past form' : ', future form'}" data-k="evo-${st}">
          <div class="pic"><img data-sprite="${spriteAttr(st, p.paletteId, st === 2 ? 'determined' : 'default', [], '', 140)}" src="${BLANK}" alt=""></div>
          <span class="lbl">${stageLabel(st)}</span></button>`)}
    </div></section>`;
}

// the next form, always on the nameplate: its silhouette, the two things it needs, and a progress ring
function evoNext(ctx) {
  const dp = ctx.d.pet;
  const p = ctx.state.pet;
  const ev = dp.evo;
  if (!ev || ev.maxed || !ev.req) return '';
  const pct = Math.min(ev.levelProgress ?? 0, ev.daysProgress ?? 0);
  return html`<button class="evo-next" data-act="inspect" data-k="evo-next" aria-label="Next form: ${stageLabel(p.stage + 1)}. Level ${dp.level} of ${ev.req.level}, ${dp.activeDays} of ${ev.req.activeDays} active days">
    <img class="sil" data-sprite="${spriteAttr(p.stage + 1, p.paletteId, 'default', [], '', 80)}" src="${BLANK}" alt="">
    <span class="t">Next: ${stageLabel(p.stage + 1)}<small>Lv ${dp.level}/${ev.req.level} · ${dp.activeDays}/${ev.req.activeDays} days</small></span>
    <i class="ring" style="--p:${pct.toFixed(3)}" aria-hidden="true"></i></button>`;
}

function evoChip(ctx) {
  const dp = ctx.d.pet;
  const p = ctx.state.pet;
  const txt = dp.evo.maxed ? 'Final form reached' : `Next: ${stageLabel(p.stage + 1)} - Lv ${dp.level}/${dp.evo.req.level}, ${dp.activeDays}/${dp.evo.req.activeDays} active days`;
  return html`<button class="card evo-chip" data-act="inspect" style="border:1.5px solid var(--card-edge);cursor:pointer;font:800 13px var(--font-game);color:var(--ink-700)" data-k="evochip"><img src="${icon('evolve')}" alt="" width="22" height="22">${txt}</button>`;
}

const COACH = [
  { t: 'Say hello!', d: 'Tap your Evochi, or use Pet and Play once a day to grow your bond.', target: '.btn-row' },
  { t: 'Walk to grow', d: 'Your daily steps turn into XP and quest rewards. Tap here to open your Journey.', target: '.steps-card' },
  { t: 'Explore', d: 'Dress up in the Bag, shop in the Market, and track discoveries in the EvoDex.', target: '.nav' },
];

function coach(ctx) {
  const u = ctx.ui('coach');
  const i = u.i || 0;
  const c = COACH[i];
  return html`<div class="coach" role="dialog" aria-label="Tips" data-coach="${c.target}">
    <div class="hole" aria-hidden="true"></div>
    <div class="bubble" style="top:120px">
      <div class="row between"><b class="h-card">${c.t}</b><span class="tiny muted">${i + 1} / ${COACH.length}</span></div>
      <p class="body" style="margin:6px 0 10px">${c.d}</p>
      <div class="row between"><button class="btn ghost" data-act="coach-done" data-k="coach-skip">Skip tips</button><button class="btn sm" data-act="coach-next" data-k="coach-next" data-autofocus>${i + 1 < COACH.length ? 'Next' : 'Got it'}</button></div>
    </div></div>`;
}

home.mount = (ctx, el) => {
  const c = el.querySelector('.coach');
  if (!c) return;
  requestAnimationFrame(() => {
    const t = el.querySelector(c.dataset.coach);
    if (!t) return;
    const r = t.getBoundingClientRect();
    const R = ctx.app.root.getBoundingClientRect();
    const hole = c.querySelector('.hole');
    Object.assign(hole.style, { left: r.left - R.left - 6 + 'px', top: r.top - R.top - 6 + 'px', width: r.width + 12 + 'px', height: r.height + 12 + 'px' });
    c.style.background = 'transparent';
    const b = c.querySelector('.bubble');
    const above = r.top - R.top > 240;
    b.style.top = above ? r.top - R.top - b.offsetHeight - 20 + 'px' : r.bottom - R.top + 20 + 'px';
    c.querySelector('[data-autofocus]')?.focus({ preventScroll: true });
  });
};

// ------------------------------------------------------------- sheets
export function openCareSheet(ctx) {
  ctx.modal({
    label: 'Care',
    render: (c) => {
      const d = c.d;
      const items = ['berry_snack', 'healing_herb'];
      const cool = d.pet.recoveryReadyAt > c.now;
      return html`<div class="stack">
        <h2 class="h-sec">Care for ${c.state.pet.name}</h2>
        <div class="row"><span class="small" style="font-weight:800">Vitality</span><div class="bar ${d.pet.vitality < 35 ? 'amber' : 'green'} grow"><i style="width:${d.pet.vitality}%"></i></div><b class="num">${d.pet.vitality}</b></div>
        ${items.map((id) => {
          const q = G.ownedQty(c.state, id);
          const it = ITEMS[id];
          const isCool = it.effect.recovery && cool;
          return html`<div class="card row" style="padding:10px"><img src="${itemImg(id)}" alt="" width="54" height="54"><div class="grow"><b class="h-card">${it.name}</b> <span class="tag small cream">x${q}</span><div class="small muted">${it.desc}</div>${isCool ? html`<div class="small" style="color:var(--gold-900);font-weight:700">Ready in ${duration(d.pet.recoveryReadyAt - c.now)}</div>` : ''}</div>
            ${q ? html`<button class="btn sm" data-act="use" data-arg="${id}" ${isCool || d.pet.vitality >= 100 ? raw('disabled') : ''}>Use</button>` : html`<button class="btn sm cream" data-act="buy" data-arg="${id}">Shop</button>`}</div>`;
        })}
        <p class="small muted" style="margin:0">Walking at least half your goal restores vitality too - care items are never required.</p>
        <button class="btn cream block" data-act="modal-close">Close</button></div>`;
    },
    actions: {
      use: (c, id) => {
        const r = c.act(G.useConsumable, id);
        if (!r.error) {
          c.toast(`+${ITEMS[id].effect.vitality} vitality`, 'ok', 'heart');
          c.scene.react('pet');
          c.sfx('reward_chime', 0.6);
        }
      },
      buy: (c, id) => {
        c.closeModal();
        c.app.ui.shop = { ...(c.app.ui.shop || {}), cat: 'care', sel: id };
        c.app.tab('shop');
      },
    },
  });
}

export function openHabitatSheet(ctx) {
  ctx.modal({
    label: 'Sunlit Meadow',
    render: (c) => {
      const s = c.state;
      const pl = s.nest.placements;
      const slots = Object.entries(DECOR_SLOTS);
      return html`<div class="stack">
        <div class="row"><img src="${icon('habitats')}" alt="" width="40" height="40"><div><h2 class="h-sec">Sunlit Meadow</h2><span class="small muted">Arrange decorations in the nest's spots.</span></div></div>
        ${slots.map(([sid, sl]) => {
          const cur = pl[sid];
          const options = Object.keys(s.inventory).filter((id) => ITEMS[id].category === 'decoration' && sl.accepts.includes(ITEMS[id].decor) && G.ownedQty(s, id) > 0);
          return html`<div class="card" style="padding:10px">
            <div class="row between"><b class="h-card">${sl.label} spot</b>${cur ? html`<button class="btn sm cream" data-act="rm" data-arg="${sid}">Remove</button>` : ''}</div>
            <div class="row" style="flex-wrap:wrap;margin-top:6px;gap:6px">
              ${options.length ? options.map((id) => html`<button class="tile" style="min-height:0;width:86px" aria-pressed="${cur === id}" data-act="place" data-arg="${sid}:${id}"><img src="${itemImg(id)}" alt="" style="width:46px;height:46px"><span class="nm">${ITEMS[id].name}</span></button>`) : html`<span class="small muted">Nothing that fits here yet - try the Market's Habitats tab.</span>`}
            </div></div>`;
        })}
        <button class="btn cream block" data-act="modal-close">Done</button></div>`;
    },
    actions: {
      place: (c, arg) => {
        const [sid, id] = arg.split(':');
        const r = c.act(G.placeDecoration, id, sid);
        if (!r.error) c.sfx('ui_tap');
      },
      rm: (c, sid) => c.act(G.removeDecoration, sid),
    },
  });
}
