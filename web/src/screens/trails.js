// Lumen Trails: the Trail Guild board, daily discoveries (and their glinting clues), encounter prep, the
// travel scene, the encounter itself (intro, turns, outro, result) and companions. No sixth tab: the
// board opens from the Village and from Journey > Daily; encounters start from a quest's "Prepare".
import * as G from '../game/state.js';
import * as Q from '../game/story.js';
import * as H from '../game/home.js';
import * as TR from '../game/trails.js';
import { ITEMS } from '../game/catalog.js';
import { html, raw, fmt, duration } from '../ui/dom.js';
import { icon, itemImg, url, manifest, spriteAttr, BLANK } from '../ui/assets.js';
import { ICON } from '../ui/icons.js';
import { coinPill, stageLabel } from '../core/app.js';
import { openStoryQuest, openStoryReward, nextText, statusTag, walkBar, npcSprite, questLead } from './village.js';

const TM = () => manifest().trails;
const SPARK = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2l2.2 7.8L22 12l-7.8 2.2L12 22l-2.2-7.8L2 12l7.8-2.2z" fill="#FFE27A" stroke="#C8832C" stroke-width="1.2" stroke-linejoin="round"/></svg>';
const KIND_TAG = { wild: ['Special Encounter', 'stage'], hollow: ['Hollow', 'hollow-tag'], boss: ['Story Boss', 'hollow-tag'] };
const INTRO_MS = { standard: 2600, rare: 4200, hollow: 4800, boss: 6400 };
const INTRO_TITLE = {
  rare: (C) => `A wild ${C.name} appeared!`, hollow: (C) => `${C.name} stirs...`, boss: (C) => C.name, standard: (C) => `${C.name} peeks out`,
};
const INTRO_SUB = { rare: 'Something rare is watching you.', hollow: 'Hollow energy pulses in the stones.', boss: 'Guardian of the Lumen Trails', standard: '' };
// where the clue glint sits on each place plate (percent of the plate)
const CLUE_SPOTS = {
  glasshouse: [68, 64], workshop: [30, 66], lodge: [72, 60], waystone: [50, 72], garden: [50, 36], cottage: [60, 60], homemap: [15, 44],
  ruins: [14, 70], gate: [86, 72],
};

// ------------------------------------------------------------------ shared bits
function hud(ctx, title, short, act = 'back') {
  return html`<header class="hud vhud"><button class="back-btn" data-act="${act}" aria-label="Back" data-k="tback">${ICON.back}</button>
    <h1 class="place-title"><span class="full">${title}</span><span class="short" aria-hidden="true">${short}</span></h1>${coinPill(ctx)}</header>`;
}

export function creatureImg(id, state, h = 120) {
  const c = TM().creatures[id];
  const st = c.states[state] ? state : Object.keys(c.states)[0];
  return html`<img src="${url(c.states[st])}" alt="" style="height:${h}px;width:auto">`;
}

function kindTag(C) {
  const [label, cls] = KIND_TAG[C.boss ? 'boss' : C.kind];
  return html`<span class="tag small ${cls}">${label}</span>`;
}

function affinityTag(aff) {
  const A = TR.AFFINITIES[aff];
  return html`<span class="tag small cream aff" style="--ac:${A.color}"><img src="${icon(A.icon)}" alt="">${A.name}</span>`;
}

function rankCard(ctx) {
  const r = ctx.d.trails.rank;
  return html`<section class="card rank-card" aria-label="Trail Guild rank ${r.name}">
    <img src="${icon('trail_badge')}" alt="" width="54" height="54">
    <div class="grow" style="min-width:0"><div class="tiny muted">Trail Guild</div><div class="row between"><b class="h-card">${r.name}</b>${r.next ? html`<span class="tiny muted">${r.into} / ${r.need} to ${r.next.name}</span>` : html`<span class="tag small ok">Top rank</span>`}</div>
      <div class="bar skill" style="--sc:#C9874E;margin-top:5px"><i style="width:${r.next ? (r.into / r.need) * 100 : 100}%"></i></div></div></section>`;
}

/** Where a discovery's "go" button should take the player. */
function placeRoute(place) {
  if (['glasshouse', 'workshop', 'lodge', 'waystone'].includes(place)) return { route: 'place', params: { id: place } };
  if (place === 'ruins' || place === 'gate') return { route: 'trailplace', params: { id: place } };
  return { route: place, params: {} };
}

function discoveryRow(ctx, d, compact = false) {
  const btn = d.phase === 'offered' ? html`<button class="btn sm green" data-act="disc-begin" data-arg="${d.id}" data-k="db-${d.id}">Begin</button>`
    : d.phase === 'walking' ? html`<button class="btn sm cream" data-act="disc-walk" data-k="dw-${d.id}"><img src="${icon('steps')}" alt="" width="18" height="18">Walk</button>`
    : d.phase === 'ready' ? html`<button class="btn sm" data-act="disc-go" data-arg="${d.id}" data-k="dg-${d.id}">Inspect</button>`
    : html`<span class="tag ok">${ICON.checkDark}Found</span>`;
  return html`<div class="card disc ${d.phase}" data-k="disc-${d.id}">
    <button class="disc-main" data-act="disc-open" data-arg="${d.id}" aria-label="${d.title}: ${d.phase === 'found' ? 'found' : d.phase === 'ready' ? 'ready to inspect at ' + d.placeName : `walk ${fmt(d.target)} steps, then inspect at ${d.placeName}`}">
      <img src="${ITEMS[d.icon] ? itemImg(d.icon) : icon(d.icon)}" alt="">
      <div style="min-width:0;text-align:left"><b class="t">${d.title}</b>
        <div class="small muted">${d.phase === 'found' ? d.found.slice(0, compact ? 60 : 90) + (d.found.length > (compact ? 60 : 90) ? '…' : '') : `Walk ${fmt(d.target)} steps, then inspect ${d.placeName}.`}</div>
        ${d.phase === 'walking' || d.phase === 'ready' ? html`<div class="bar green" style="margin-top:5px"><i style="width:${d.pct * 100}%"></i></div><div class="tiny muted" style="margin-top:2px">${fmt(d.walked)} / ${fmt(d.target)} steps${d.phase === 'ready' ? ' ✓' : ''}</div>` : ''}
        ${!compact && d.phase !== 'found' ? html`<div class="row" style="gap:4px;margin-top:5px;flex-wrap:wrap"><span class="reward-chip mini"><img src="${icon('coin')}" alt="">${d.reward.coins}</span>${Object.entries(d.reward.items || {}).map(([id, n]) => html`<span class="reward-chip mini"><img src="${itemImg(id)}" alt="">${n > 1 ? 'x' + n : ''}</span>`)}<span class="reward-chip mini"><img src="${icon('trail_badge')}" alt="">+${d.reward.guildXp} Guild</span></div>` : ''}</div>
    </button>
    <div class="acts">${btn}</div></div>`;
}

/** Journey > Daily: today's discoveries in brief. */
export function discoveriesPanel(ctx) {
  const t = ctx.d.trails;
  if (!t) return '';
  return html`<section class="card" style="padding:12px" aria-label="Trail Guild discoveries">
    <div class="row between"><h2 class="h-card row" style="gap:6px"><img src="${icon('discover')}" alt="" width="24" height="24">Today's discoveries</h2><span class="tiny muted">Resets in ${duration(t.msToReset)}</span></div>
    <p class="small muted" style="margin:4px 0 8px">The Trail Guild posts three small adventures a day: walk, then inspect the place.</p>
    <div class="list">${t.discoveries.map((d) => discoveryRow(ctx, d, true))}</div>
    <button class="btn cream block" style="margin-top:10px" data-act="guild" data-k="j-guild"><img src="${icon('trail_badge')}" alt="" width="22" height="22"><span>Open the Guild Board</span></button></section>`;
}

/** Home: one compact row when a discovery is ready or still unstarted today. */
export function discoveryChip(ctx) {
  const t = ctx.d.trails;
  if (!t || ctx.H < 640) return '';
  const d = t.ready[0] || (t.foundToday === 0 && t.walking.length === 0 ? t.offered[0] : null);
  if (!d) return '';
  return html`<button class="card story-chip disc-chip" data-act="disc-chip" data-arg="${d.id}" data-k="disc-chip">
    <img src="${icon('discover')}" alt="">
    <div style="min-width:0"><div class="t">${d.phase === 'ready' ? 'Discovery ready!' : 'New Daily Discovery!'}</div><div class="d">${d.phase === 'ready' ? `Inspect ${d.placeName}: ${d.title}` : d.title}</div></div>
    <span class="chev" aria-hidden="true">&rsaquo;</span></button>`;
}

/** A glinting clue on a place plate while a discovery is ready there. */
export function clueGlint(ctx, place) {
  const clues = TR.cluesAt(ctx.state, place, ctx.now);
  if (!clues.length) return '';
  const [x, y] = CLUE_SPOTS[place] || [50, 60];
  return html`<button class="clue" data-act="clue" data-arg="${clues[0].id}" data-k="clue" style="left:${x}%;top:${y}%" aria-label="Inspect: ${clues[0].title}">
    ${raw(SPARK)}<span>Inspect</span></button>`;
}

export function openDiscovery(ctx, id) {
  ctx.modal({
    label: TR.DISCOVERIES[id].title,
    render: (c) => {
      const d = TR.discoveryView(c.state, id, c.now);
      return html`<div class="stack">
        <div class="row" style="gap:10px"><img src="${icon('discover')}" alt="" width="48" height="48"><div><div class="tiny muted">Trail Guild discovery</div><h2 class="h-sec">${d.title}</h2></div></div>
        <p class="body" style="margin:0">${d.phase === 'found' ? d.found : d.clue}</p>
        ${d.phase !== 'found' ? html`<div class="card inset" style="padding:10px"><b class="small">Walk ${fmt(d.target)} steps, then inspect ${d.placeName}</b>
          ${d.phase !== 'offered' ? html`<div class="bar green" style="margin-top:6px"><i style="width:${d.pct * 100}%"></i></div><div class="tiny muted" style="margin-top:3px">${fmt(d.walked)} / ${fmt(d.target)} new steps${d.phase === 'ready' ? ' ✓ ready' : ''}</div>` : html`<div class="tiny muted" style="margin-top:3px">Only steps after you begin count.</div>`}</div>` : ''}
        <div><div class="small" style="font-weight:800;margin-bottom:6px">Reward</div><div class="row" style="flex-wrap:wrap;gap:6px">
          <span class="reward-chip"><img src="${icon('coin')}" alt=""><span>${d.reward.coins}</span></span>
          ${Object.entries(d.reward.items || {}).map(([iid, n]) => html`<span class="reward-chip"><img src="${itemImg(iid)}" alt=""><span>${n} × ${ITEMS[iid].name}</span></span>`)}
          <span class="reward-chip"><img src="${icon('trail_badge')}" alt=""><span>+${d.reward.guildXp} Guild XP</span></span></div></div>
        ${d.phase === 'offered' ? html`<button class="btn green block" data-act="dm-begin" data-autofocus>Begin</button>` : ''}
        ${d.phase === 'walking' ? html`<button class="btn green block" data-act="dm-walk" data-autofocus>Go for a walk</button>` : ''}
        ${d.phase === 'ready' ? html`<button class="btn block" data-act="dm-go" data-autofocus>Go to ${d.placeName}</button>` : ''}
        <button class="btn cream block" data-act="modal-close">Close</button></div>`;
    },
    actions: {
      'dm-begin': (c) => {
        const r = c.act(TR.beginDiscovery, id);
        if (!r.error) {
          c.sfx('reward_chime', 0.5);
          c.app.renderModals();
        }
      },
      'dm-walk': (c) => {
        c.closeModal();
        c.app.ui.journey = { ...(c.app.ui.journey || {}), tab: 'daily' };
        c.app.tab('journey');
      },
      'dm-go': (c) => {
        c.closeModal();
        const r = placeRoute(TR.DISCOVERIES[id].place);
        c.go(r.route, r.params);
      },
    },
  });
}

/** Tapping the glint: the find, its text and rewards. */
export function inspectClue(ctx, id) {
  const r = ctx.act(TR.inspectDiscovery, id);
  if (r.error) return;
  ctx.sfx('reward_chime');
  const d = TR.DISCOVERIES[id];
  const rank = r.events.find((e) => e.type === 'guild_rank');
  ctx.modal({
    center: true,
    label: 'Discovery',
    render: () => html`<div class="stack center">
      <div class="story-banner">Found it!</div>
      <h2 class="h-sec" style="margin:0">${d.title}</h2>
      <p class="body" style="margin:0">${d.found}</p>
      <div class="row" style="justify-content:center;gap:8px;flex-wrap:wrap">
        <span class="tag stage" style="height:34px;font-size:16px"><img src="${icon('coin')}" alt="" style="width:24px;height:24px">+${d.reward.coins}</span>
        ${Object.entries(d.reward.items || {}).map(([iid, n]) => html`<span class="tag cream" style="height:34px;font-size:14px"><img src="${itemImg(iid)}" alt="" style="width:26px;height:26px">${n} × ${ITEMS[iid].name}</span>`)}
        <span class="tag ok" style="height:34px;font-size:14px"><img src="${icon('trail_badge')}" alt="" style="width:24px;height:24px">+${d.reward.guildXp} Guild XP</span></div>
      ${rank ? html`<div class="card inset" style="padding:8px 12px"><b class="small">Guild rank up: ${rank.rank.name}!</b></div>` : ''}
      <button class="btn block" data-act="modal-close" data-autofocus>Lovely</button></div>`,
  });
}

const discoveryActions = {
  'disc-begin'(ctx, id) {
    const r = ctx.act(TR.beginDiscovery, id);
    if (!r.error) ctx.sfx('reward_chime', 0.5);
  },
  'disc-walk'(ctx) {
    ctx.app.ui.journey = { ...(ctx.app.ui.journey || {}), tab: 'daily' };
    ctx.app.tab('journey');
  },
  'disc-go'(ctx, id) {
    const r = placeRoute(TR.DISCOVERIES[id].place);
    ctx.go(r.route, r.params);
  },
  'disc-open'(ctx, id) {
    openDiscovery(ctx, id);
  },
  'disc-chip'(ctx, id) {
    const d = TR.discoveryView(ctx.state, id, ctx.now);
    if (d.phase === 'ready') {
      const r = placeRoute(d.place);
      ctx.go(r.route, r.params);
    } else openDiscovery(ctx, id);
  },
  clue(ctx, id) {
    inspectClue(ctx, id);
  },
  guild(ctx) {
    ctx.sfx('ui_tap', 0.4);
    ctx.go('guild');
  },
  quest(ctx, id) {
    openStoryQuest(ctx, id);
  },
  prep(ctx, id) {
    ctx.go('prep', { id });
  },
};
export { discoveryActions };

// ------------------------------------------------------------------ Guild Board
function trailQuestRow(ctx, v) {
  const E = TR.ENCOUNTERS[v.id];
  const C = TR.CREATURES[E.creature];
  const ready = v.next.kind === 'encounter';
  return html`<button class="card story-quest trail-quest ${v.completed ? 'claimed' : ''}" data-act="${ready ? 'prep' : 'quest'}" data-arg="${v.id}" data-k="tq-${v.id}">
    <span class="face cr"><img src="${icon('creature_' + E.creature)}" alt="" style="${v.completed || v.accepted ? '' : 'filter:brightness(0) opacity(.35)'}"></span>
    <div style="min-width:0;text-align:left"><div class="row" style="gap:6px;flex-wrap:wrap"><span class="t">${v.title}</span>${statusTag(v)}</div>
      <div class="row" style="gap:4px;margin:3px 0;flex-wrap:wrap">${kindTag(C)}${affinityTag(C.affinity)}</div>
      <div class="small muted">${ready ? `Ready: travel to ${TR.PLACE_NAMES[E.place]}` : nextText(v)}</div>
      ${v.accepted && !v.completed ? html`<div style="margin-top:4px">${walkBar(v)}</div>` : ''}</div>
    <span class="chev" aria-hidden="true">&rsaquo;</span></button>`;
}

export const guild = {
  id: 'guild',
  scene: () => null,
  mount(ctx) {
    if (!ctx.d.trails.seen.guild_intro) setTimeout(() => ctx.act(TR.markTrailSeen, 'guild_intro'), 0);
  },
  render(ctx) {
    const t = ctx.d.trails;
    const st = ctx.d.story;
    const u = ctx.ui('guild');
    const firstVisit = !t.seen.guild_intro;
    return html`<main class="screen scroll paper village guild" aria-label="Trail Guild Board">
      ${hud(ctx, 'Trail Guild Board', 'Guild')}
      <div class="guild-head"><img class="plate" src="${url(manifest().village.places.lodge.file)}" alt="">
        <div class="guild-title"><img src="${icon('trail_badge')}" alt="" width="40" height="40"><div><div class="tiny" style="color:#FFF6E6">Sunlit Village</div><b class="h-sec" style="color:#FFF">Trail Guild</b></div></div></div>
      <div class="pad stack" style="gap:10px;margin-top:-16px;position:relative;z-index:3;padding-bottom:calc(20px + var(--safe-bottom))">
        ${rankCard(ctx)}
        ${firstVisit || u.lore ? html`<section class="card lore-card" aria-label="${TR.LORE.title}">
          <div class="row between"><h2 class="h-card">${TR.LORE.title}</h2><button class="btn ghost" data-act="lore" data-k="lore-toggle">${u.lore || firstVisit ? 'Hide' : 'Read'}</button></div>
          <p class="body" style="margin:6px 0 0">${TR.LORE.intro}</p><p class="body" style="margin:6px 0 0">${TR.LORE.trails}</p><p class="small muted" style="margin:6px 0 0">${TR.LORE.guild}</p></section>`
        : html`<button class="card row lore-row" data-act="lore" data-k="lore-toggle"><img src="${icon('trail')}" alt="" width="36" height="36"><div class="grow" style="text-align:left"><b class="h-card">${TR.LORE.title}</b><div class="small muted">Why your steps light the trails</div></div><span class="chev" aria-hidden="true">&rsaquo;</span></button>`}
        <div class="row between"><h2 class="h-sec sec-head">Today's discoveries</h2><span class="tiny muted">Resets in ${duration(t.msToReset)}</span></div>
        <div class="list">${t.discoveries.map((d) => discoveryRow(ctx, d))}</div>
        <h2 class="h-sec sec-head">Trail jobs <span class="tag small cream" style="margin-left:4px">Encounters</span></h2>
        <div class="list">${st.trail.map((v) => trailQuestRow(ctx, v))}</div>
        ${t.companions.length || Object.keys(t.restored).length ? html`<h2 class="h-sec sec-head">Friends of the trail</h2>
          <div class="friend-grid">${t.companions.map((c) => html`<button class="friend-card" data-act="friend" data-arg="${c.id}" data-k="fr-${c.id}"><img src="${icon('creature_' + c.id)}" alt=""><b>${c.name}</b><span class="tiny muted">Companion</span></button>`)}
            ${Object.keys(t.restored).map((id) => html`<button class="friend-card" data-act="friend" data-arg="${id}" data-k="fr-${id}"><img src="${icon('creature_' + id)}" alt=""><b>${TR.CREATURES[id].name}</b><span class="tiny muted">Restored</span></button>`)}</div>` : ''}
        <p class="small muted" style="margin:2px 4px">Discoveries are cozy and quick. Encounters are optional, and never a fight to the finish: you calm, befriend and restore. Your Evochi never faints.</p>
      </div>
    </main>`;
  },
  actions: {
    ...discoveryActions,
    lore(ctx) {
      const u = ctx.ui('guild');
      u.lore = !u.lore;
      if (!ctx.d.trails.seen.guild_intro) ctx.act(TR.markTrailSeen, 'guild_intro');
      ctx.rerender();
    },
    friend(ctx, id) {
      openCreatureCard(ctx, id);
    },
  },
};

export function openCreatureCard(ctx, id) {
  const C = TR.CREATURES[id];
  const t = ctx.d.trails;
  const comp = t.companions.find((c) => c.id === id);
  const restored = t.restored[id];
  ctx.modal({
    label: C.name,
    render: () => html`<div class="stack center">
      <div class="friend-hero">${creatureImg(id, C.states.done, C.size === 'large' ? 150 : 120)}</div>
      <h2 class="h-sec" style="margin:0">${C.name}</h2>
      <div class="row" style="justify-content:center;gap:4px;flex-wrap:wrap">${kindTag(C)}${affinityTag(C.affinity)}${C.traits.slice(1).map((tr) => html`<span class="tag small cream">${tr}</span>`)}</div>
      <p class="body" style="margin:0">${C.blurb}</p>
      <div class="kv card inset" style="padding:10px 12px;text-align:left;width:100%">
        <span>Found</span><b>${C.home}</b>
        ${comp ? html`<span>Companion since</span><b>${new Date(comp.since).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}</b>` : ''}
        ${restored ? html`<span>Restored</span><b>${new Date(restored).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}</b>` : ''}
        ${C.companion ? html`<span>In encounters</span><b>${C.companion.name}</b>` : ''}
      </div>
      ${C.companion && comp ? html`<p class="small muted" style="margin:0">${C.companion.text}</p>` : ''}
      <button class="btn cream block" data-act="modal-close" data-autofocus>Close</button></div>`,
  });
}

/** EvoDex: companions and restored guardians. */
export function friendsPanel(ctx) {
  const t = ctx.d.trails;
  if (!t) return '';
  const all = Object.values(TR.CREATURES);
  const known = (id) => t.companions.some((c) => c.id === id) || !!t.restored[id];
  return html`<section class="card" style="padding:12px" aria-label="Friends of the trail">
    <div class="row between"><h2 class="h-card">Friends of the trail</h2><span class="tag small cream">${all.filter((c) => known(c.id)).length} / ${all.length} met</span></div>
    <div class="friend-grid" style="margin-top:8px">${all.map((c) => html`<button class="friend-card ${known(c.id) ? '' : 'unknown'}" data-act="${known(c.id) ? 'friend' : ''}" data-arg="${c.id}" data-k="dxf-${c.id}" aria-label="${known(c.id) ? c.name : 'Not met yet'}">
      <img src="${icon('creature_' + c.id)}" alt="" style="${known(c.id) ? '' : 'filter:brightness(0) opacity(.3)'}"><b>${known(c.id) ? c.name : '???'}</b><span class="tiny muted">${known(c.id) ? (t.restored[c.id] ? 'Restored' : 'Companion') : c.boss ? 'A story boss' : c.kind === 'hollow' ? 'A Hollow' : 'A wild Evochi'}</span></button>`)}</div>
    <p class="small muted" style="margin:8px 0 0">Befriended Evochi visit your nest and help in encounters. Restored guardians light the Lumen Trails. Both are found through Trail Guild jobs.</p></section>`;
}

// ------------------------------------------------------------------ trail places (ruins, gate)
export const trailplace = {
  id: 'trailplace',
  scene: () => null,
  render(ctx) {
    const id = ctx.app.route.params.id === 'gate' ? 'gate' : 'ruins';
    const st = ctx.d.story;
    const sceneId = id === 'gate' ? 'sentinel_gate' : st.flags.sprout_restored || !st.flags.petalune_befriended ? 'mossy_ruins' : Q.questPhase(ctx.state, 'eq02') === 'ruins_ready' || Q.questPhase(ctx.state, 'eq02') === 'accepted_walk' ? 'mossy_ruins_hollow' : 'mossy_ruins';
    const sc = TM().scenes[sceneId];
    const name = id === 'gate' ? 'The Old Gate' : 'Mossy Ruins';
    const quest = st.trail.find((v) => v.next.place === id && v.accepted && !v.completed) || null;
    const t = ctx.d.trails;
    const friends = id === 'ruins' ? ['petalune', 'hollow_sprout'].filter((c) => t.companions.some((x) => x.id === c) || t.restored[c]) : t.restored.sentinel ? ['sentinel'] : [];
    return html`<main class="screen scroll paper village trailplace" aria-label="${name}">
      ${hud(ctx, name, name.replace('The ', ''))}
      <div class="trail-plate" style="aspect-ratio:${sc.w} / ${Math.round(sc.h * 0.8)}">
        <img class="plate" src="${url(sc.file)}" alt="${id === 'gate' ? 'A great broken gate at dusk, Hollow crystals glowing around it.' : 'A quiet forest ruin: a mossy arch, flagstones and a waterfall.'}">
        ${friends.map((c) => html`<img class="resident ${TR.CREATURES[c].size}" src="${url(TM().creatures[c].states[TR.CREATURES[c].states.done])}" alt="${TR.CREATURES[c].name}" style="left:${(sc.anchors.wild[0] / sc.w) * 100}%;top:${(sc.anchors.wild[1] / sc.h) * 100}%">`)}
        ${clueGlint(ctx, id)}
      </div>
      <div class="pad stack" style="gap:10px;margin-top:-14px;position:relative;z-index:3;padding-bottom:calc(20px + var(--safe-bottom))">
        ${quest ? html`<button class="card story-strip" data-act="${quest.next.kind === 'encounter' ? 'prep' : 'quest'}" data-arg="${quest.id}" data-k="tp-quest">
          <span class="face cr"><img src="${icon('creature_' + TR.ENCOUNTERS[quest.id].creature)}" alt=""></span>
          <div class="grow" style="min-width:0;text-align:left"><div class="tiny muted">Trail job</div><b class="h-card">${quest.title}</b><div class="small" style="color:var(--ink-700)">${nextText(quest)}</div></div>
          <span class="chev" aria-hidden="true">&rsaquo;</span></button>` : ''}
        <p class="body" style="margin:2px 4px">${id === 'gate' ? (t.restored.sentinel ? 'The gate stands open. Beyond it the third trail glows faintly, on and on past the horizon.' : 'The bridge creaks but holds. Past it, the old gate waits in the dusk, humming with Hollow light.')
          : t.restored.hollow_sprout ? 'The ruins are peaceful now. Petals drift from the arch, and the little sprout waves at everyone who passes.'
          : st.flags.petalune_befriended ? 'The ruins are quiet. Somewhere under the moss, trail runes point north.' : 'A quiet ruin where the forest has taken the stones back. Runes under the moss, a waterfall behind the arch.'}</p>
        ${friends.length ? html`<div class="row" style="gap:8px;flex-wrap:wrap">${friends.map((c) => html`<button class="tag cream" style="height:34px;cursor:pointer" data-act="friend" data-arg="${c}" data-k="tpf-${c}"><img src="${icon('creature_' + c)}" alt="" style="width:24px;height:24px">${TR.CREATURES[c].name}</button>`)}</div>` : ''}
        ${TR.cluesAt(ctx.state, id, ctx.now).length ? html`<p class="small" style="margin:0 4px;color:var(--gold-900);font-weight:800">Something glints here. Tap it to inspect.</p>` : ''}
      </div>
    </main>`;
  },
  actions: {
    ...discoveryActions,
    friend(ctx, id) {
      openCreatureCard(ctx, id);
    },
  },
};

// ------------------------------------------------------------------ encounter prep
function reqRow(ok, img, text, sub, optional = false) {
  return html`<div class="req-row ${ok ? 'ok' : ''} ${optional ? 'opt' : ''}"><span class="ck" aria-hidden="true">${ok ? ICON.check : ''}</span><img src="${img}" alt=""><div class="grow"><b class="small">${text}</b>${sub ? html`<div class="tiny muted">${sub}</div>` : ''}</div>${optional ? html`<span class="tag small cream">Optional</span>` : ''}</div>`;
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
    const walkDone = v.walk && (v.phase !== Q.QUESTS[qid].walk.phase && v.accepted);
    const needs = Q.itemNeeds(ctx.state, t);
    const opts = Object.entries(t.optionalItems || {}).map(([id, nn]) => ({ id, need: nn, have: G.ownedQty(ctx.state, id), ok: G.ownedQty(ctx.state, id) >= nn }));
    const ready = n.kind === 'encounter';
    const stageOk = (pet?.stage || 1) >= (E.recommended.stage || 1);
    const r = v.rewards;
    const going = n.kind === 'gather' ? needs.find((x) => !x.ok) : null;
    const src = going ? H.homeSource(going.id) : null;
    return html`<main class="screen scroll paper village prep" aria-label="Encounter preparation">
      ${hud(ctx, 'Encounter Prep', 'Prepare')}
      <div class="pad stack" style="gap:10px;padding-top:6px;padding-bottom:calc(20px + var(--safe-bottom))">
        <section class="card prep-hero ${C.kind}">
          <div class="pic">${creatureImg(E.creature, C.states.start, C.size === 'large' ? 150 : 118)}</div>
          <div class="grow" style="min-width:0"><div class="tiny muted">${questLead(v)}</div><h2 class="h-sec">${v.title}</h2>
            <div class="row" style="gap:4px;margin-top:4px;flex-wrap:wrap">${kindTag(C)}${affinityTag(C.affinity)}</div>
            <p class="small" style="margin:6px 0 0;color:var(--ink-700)">${E.goal === 'befriend' ? `Goal: fill ${C.name}'s Calm meter. It joins you as a companion.` : `Goal: bring ${C.name}'s Instability to zero and restore it.`}</p></div>
        </section>
        <section class="card" style="padding:12px"><h3 class="h-card" style="margin:0 0 8px">Requirements</h3>
          ${v.phase === 'available' || v.phase === 'locked' ? reqRow(false, npcSprite(Q.QUESTS[qid].giver, 'neutral'), `Talk to ${Q.NPCS[Q.QUESTS[qid].giver].name}`, v.phase === 'locked' ? v.lock.text : 'Accept the job at the Trail Guild') : ''}
          ${v.walk ? reqRow(!!walkDone, icon('steps'), `Walk ${fmt(v.resolved)} steps`, walkDone ? 'Done' : v.accepted ? `${fmt(v.walk.progress || 0)} / ${fmt(v.resolved)} new steps` : 'Counts after you accept') : ''}
          ${needs.map((x) => reqRow(x.ok, itemImg(x.id), `Bring ${x.need} × ${ITEMS[x.id].name}`, `${x.have} / ${x.need} in your Bag`))}
          ${opts.map((x) => reqRow(x.ok, itemImg(x.id), `Bring ${x.need} × ${ITEMS[x.id].name}`, x.ok ? 'Ready to offer' : 'Better results, never required', true))}
        </section>
        <section class="card" style="padding:12px"><h3 class="h-card" style="margin:0 0 8px">Recommended</h3>
          <div class="req-row ${stageOk ? 'ok' : ''}"><span class="ck" aria-hidden="true">${stageOk ? ICON.check : ''}</span>${pet ? html`<img data-sprite="${spriteAttr(pet.stage, pet.paletteId, 'default', [], '', 60)}" src="${BLANK}" alt="">` : ''}<div class="grow"><b class="small">${E.recommended.stage > 1 ? `A ${stageLabel(E.recommended.stage)} or older Evochi` : 'Any Evochi'}</b><div class="tiny muted">${pet ? `${pet.name} is ${stageLabel(pet.stage) === 'Eggling' ? 'an' : 'a'} ${stageLabel(pet.stage)} · ${TR.maxEnergy(ctx.state)} Energy` : ''}${!stageOk ? ' · a grown Evochi has more Energy' : ''}</div></div></div>
          <div class="req-row ok"><span class="ck" aria-hidden="true">${ICON.check}</span><img src="${icon(TR.AFFINITIES[E.recommended.affinity].icon)}" alt=""><div class="grow"><b class="small">${TR.AFFINITIES[E.recommended.affinity].name} affinity${ctx.d.trails.companions.some((c) => c.id === 'petalune') && E.creature !== 'petalune' ? ': Petalune will help' : ''}</b><div class="tiny muted">${E.goal === 'restore' ? 'Lumen Glow hits the Hollow harder' : `${C.name} loves ${C.likes.map((i) => ITEMS[i].name).join(', ')}`}</div></div></div>
        </section>
        <section class="card" style="padding:12px"><h3 class="h-card" style="margin:0 0 8px">Possible rewards</h3>
          <div class="row" style="flex-wrap:wrap;gap:6px">
            ${r.companion ? html`<span class="reward-chip story"><img src="${icon('creature_' + r.companion)}" alt=""><span>${TR.CREATURES[r.companion].name} joins you</span></span>` : ''}
            ${(r.items || []).map((id) => html`<span class="reward-chip story"><img src="${itemImg(id)}" alt=""><span>${ITEMS[id].name}</span></span>`)}
            ${r.coins ? html`<span class="reward-chip"><img src="${icon('coin')}" alt=""><span>${r.coins}</span></span>` : ''}
            ${Object.entries(r.gifts || {}).map(([id, nn]) => html`<span class="reward-chip"><img src="${itemImg(id)}" alt=""><span>${nn} × ${ITEMS[id].name}</span></span>`)}
            ${(r.titles || []).map((tt) => html`<span class="reward-chip"><img src="${icon('crown')}" alt=""><span>Title: ${Q.TITLES[tt].name}</span></span>`)}
            ${(r.unlocks || []).map((uu) => html`<span class="reward-chip unlock"><img src="${icon('star')}" alt=""><span>${uu}</span></span>`)}</div></section>
        ${ready ? html`<button class="btn green block" data-act="travel" data-k="travel">${raw(SPARK)}<span>Prepare &amp; Travel</span></button>`
          : v.phase === 'available' ? html`<button class="btn block" data-act="talk" data-k="talk">Talk to ${Q.NPCS[Q.QUESTS[qid].giver].name}</button>`
          : n.kind === 'walk' ? html`<button class="btn green block" data-act="walk" data-k="p-walk">Go for a walk</button>`
          : going && src ? html`<button class="btn green block" data-act="home" data-arg="${src.route === 'station' ? src.station : 'garden'}" data-k="p-home">${src.verb} ${ITEMS[going.id].name} in your ${src.place}</button>`
          : v.completed ? html`<div class="card inset center" style="padding:10px"><b class="small">Complete. ${E.goal === 'befriend' ? `${C.name} is your companion.` : `${C.name} was restored.`}</b></div>` : ''}
        ${ready && opts.some((x) => !x.ok) ? html`<p class="small muted center" style="margin:0">You can go now, or bring ${opts.filter((x) => !x.ok).map((x) => ITEMS[x.id].name).join(' / ')} first.</p>` : ''}
        <button class="btn cream block" data-act="quest" data-arg="${qid}" data-k="p-details">Quest details</button>
      </div>
    </main>`;
  },
  actions: {
    quest(ctx, id) {
      openStoryQuest(ctx, id);
    },
    travel(ctx) {
      const qid = ctx.app.route.params.id;
      const r = ctx.act(TR.startEncounter, qid);
      if (r.error) return;
      ctx.ui('encounter').phase = null;
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

// ------------------------------------------------------------------ travel
const TRAVEL_LINES = {
  eq01: ['You follow the petals along the old trail.', 'The forest hushes. Moss, flagstones, the sound of water.', 'You arrive at a quiet ruin. Something small is watching from the arch.'],
  eq02: ['The Lumen Trace hums in your pocket as you walk.', 'Purple light flickers between the stones ahead.', 'You arrive at the ruins. The vines have grown thick, and they glow.'],
  eq03: ['The north road is overgrown, but the map is clear.', 'The old bridge creaks under your feet, and holds.', 'Beyond it, in the dusk, a gate. And in the gate, something that remembers you.'],
};

export const travel = {
  id: 'travel',
  scene: () => null,
  mount(ctx, el) {
    const u = ctx.ui('travel');
    if (u.timer) clearTimeout(u.timer);
    u.route = ctx.app.route;
    const qid = ctx.app.route.params.id;
    const lines = TRAVEL_LINES[qid] || TRAVEL_LINES.eq01;
    u.i = 0;
    const step = () => {
      if (u.route !== ctx.app.route || !el.isConnected) return;
      u.i++;
      const t = el.querySelector('.travel-text');
      if (t && u.i < lines.length) {
        t.classList.remove('in');
        void t.offsetWidth;
        t.textContent = lines[u.i];
        t.classList.add('in');
        u.timer = setTimeout(step, ctx.app.reducedMotion ? 1200 : 2200);
      } else if (u.i >= lines.length) {
        el.querySelector('.travel-cta')?.classList.add('show');
      }
    };
    u.timer = setTimeout(step, ctx.app.reducedMotion ? 1000 : 2200);
  },
  render(ctx) {
    const qid = TR.ENCOUNTERS[ctx.app.route.params.id] ? ctx.app.route.params.id : 'eq01';
    const E = TR.ENCOUNTERS[qid];
    const sc = TM().scenes[E.scene];
    const lines = TRAVEL_LINES[qid] || TRAVEL_LINES.eq01;
    return html`<main class="screen travel ${E.scene}" aria-label="Travelling">
      <div class="travel-plate"><img class="plate pan" src="${url(sc.file)}" alt=""></div>
      <div class="travel-fade"></div>
      <header class="hud vhud" style="position:absolute;left:0;right:0;top:0"><button class="back-btn" data-act="skip" aria-label="Skip" data-k="t-skip">${ICON.back}</button><h1 class="place-title"><span class="full">${TR.PLACE_NAMES[E.place].replace('the ', 'The ')}</span><span class="short" aria-hidden="true">Travel</span></h1><span style="width:44px"></span></header>
      <div class="travel-bottom">
        <div class="card travel-card"><p class="travel-text in">${lines[0]}</p></div>
        <button class="btn green block travel-cta" data-act="arrive" data-k="arrive">Continue</button>
        <button class="btn ghost block" data-act="arrive" data-k="t-skip2" style="color:#FFF6E6">Skip</button>
      </div>
    </main>`;
  },
  actions: {
    arrive(ctx) {
      const u = ctx.ui('travel');
      if (u.timer) clearTimeout(u.timer);
      ctx.ui('encounter').phase = 'intro';
      ctx.go('encounter', { id: ctx.app.route.params.id }, { replace: true });
    },
    skip(ctx) {
      travel.actions.arrive(ctx);
    },
  },
};

// ------------------------------------------------------------------ encounter
function meterBar(label, pct, kind, shown, max) {
  return html`<div class="meter ${kind}"><div class="row between"><b class="tiny">${label}</b><span class="tiny num">${shown}${max ? ' / ' + max : ''}</span></div>
    <div class="bar"><i style="width:${Math.max(0, Math.min(100, pct * 100))}%"></i></div></div>`;
}

function petExpr(u, v) {
  if (v.done === 'success') return 'excited';
  if (u.lastWild?.energy) return 'surprised';
  if (u.lastYou === 'restore') return 'sleepy';
  if (u.lastYou) return 'determined';
  return 'default';
}

export const encounter = {
  id: 'encounter',
  scene: () => null,
  mount(ctx, el) {
    const u = ctx.ui('encounter');
    const v = ctx.d.trails?.encounter;
    if (!v) return;
    if (u.phase === 'intro' && !u.introTimer) {
      const ms = ctx.app.reducedMotion ? 900 : INTRO_MS[v.intro] || 3000;
      u.introTimer = setTimeout(() => {
        u.introTimer = null;
        if (u.phase === 'intro') {
          u.phase = 'card';
          ctx.rerender();
        }
      }, ms);
    }
    if (u.phase === 'outro' && !u.outroTimer) {
      u.outroTimer = setTimeout(() => {
        u.outroTimer = null;
        if (u.phase === 'outro') {
          u.phase = 'result';
          ctx.rerender();
        }
      }, ctx.app.reducedMotion ? 600 : 2600);
    }
  },
  render(ctx) {
    const v = ctx.d.trails?.encounter;
    const u = ctx.ui('encounter');
    if (!v) {
      // nothing running: bounce back to the Guild
      setTimeout(() => ctx.go('guild', {}, { replace: true }), 0);
      return html`<main class="screen paper"></main>`;
    }
    if (!u.phase) u.phase = 'play';
    if (v.done === 'success' && u.phase === 'play') u.phase = 'outro';
    const C = v.creature;
    const sc = TM().scenes[v.scene];
    const cr = TM().creatures[C.id];
    const pet = ctx.state.pet;
    const phase = u.phase;
    const hollowLook = C.kind === 'hollow' && v.done !== 'success';
    const wildPos = sc.anchors.wild;
    const petPos = sc.anchors.pet;
    const wildW = C.size === 'large' ? 56 : 32;
    const introOn = phase === 'intro';
    const cardOn = phase === 'card';
    const outroOn = phase === 'outro';
    const resultOn = phase === 'result';
    const wildState = v.stateKey;
    const items = v.items;
    const lastLog = v.log[v.log.length - 1];
    const prevLog = v.log[v.log.length - 2];
    return html`<main class="screen enc ${v.intro} ${hollowLook ? 'hollow' : ''} ${phase} ${v.phase2 ? 'phase2' : ''}" aria-label="Encounter with ${C.name}">
      <div class="enc-stage" style="aspect-ratio:${sc.w} / ${Math.round(sc.h * 0.92)}">
        <img class="plate" src="${url(sc.file)}" alt="">
        <div class="enc-dim" aria-hidden="true"></div>
        ${v.intro === 'rare' ? html`<div class="petals" aria-hidden="true">${[0, 1, 2, 3, 4, 5, 6, 7].map((i) => html`<i style="--i:${i}"></i>`)}</div>` : ''}
        ${hollowLook ? html`<div class="hollow-pulse" aria-hidden="true"></div>` : ''}
        ${v.done === 'success' ? html`<div class="motes" aria-hidden="true">${[0, 1, 2, 3, 4, 5, 6, 7, 8, 9].map((i) => html`<i style="--i:${i}">${raw(SPARK)}</i>`)}</div>` : ''}
        <div class="enc-wild ${wildState} ${C.size} ${u.wildHit && !v.done ? 'hit' : ''} ${v.mood}" style="left:${(wildPos[0] / sc.w) * 100}%;top:${(wildPos[1] / sc.h) * 100}%;width:${wildW}%" aria-label="${C.name}, ${v.meterLabel} ${v.meterShown}">
          <img src="${url(cr.states[wildState])}" alt="" style="aspect-ratio:${cr.w} / ${cr.h}">
          ${introOn && v.intro !== 'boss' ? html`<span class="bang" aria-hidden="true">!</span>` : ''}
          ${u.floatWild && !v.done ? html`<span class="float wild-f ${u.floatWild > 0 ? 'good' : 'bad'}" key="${v.turn}">${u.floatWild > 0 ? '+' : ''}${u.floatWild}</span>` : ''}
        </div>
        ${pet ? html`<div class="enc-pet ${u.lastYou || ''} ${v.done === 'success' ? 'joy' : ''}" style="left:${Math.max(19, (petPos[0] / sc.w) * 100)}%;top:${(petPos[1] / sc.h) * 100}%">
          <img data-sprite="${spriteAttr(pet.stage, pet.paletteId, petExpr(u, v), Object.values(pet.equipped || {}), '', 200)}" src="${BLANK}" alt="${pet.name}">
          ${u.floatYou && !v.done ? html`<span class="float you-f good">+${u.floatYou} ${v.meterLabel}</span>` : ''}
        </div>` : ''}
        <div class="enc-card wild-card ${introOn ? 'hide' : ''}"><div class="row between" style="gap:6px"><b class="nm">${C.name}</b><img src="${icon(TR.AFFINITIES[C.affinity].icon)}" alt="${TR.AFFINITIES[C.affinity].name}" width="20" height="20"></div>
          ${meterBar(v.meterLabel, v.pct, v.goal === 'befriend' ? 'calm' : 'inst', v.meterShown, v.max)}</div>
        ${pet ? html`<div class="enc-card pet-card ${introOn ? 'hide' : ''}"><div class="row between" style="gap:6px"><b class="nm">${pet.name}</b><span class="tag small cream">Lv ${ctx.d.pet.level}</span></div>
          ${meterBar('Energy', v.energy / v.energyMax, 'energy', v.energy, v.energyMax)}</div>` : ''}
        ${introOn ? html`<div class="intro-title ${v.intro}"><b>${INTRO_TITLE[v.intro](C)}</b>${INTRO_SUB[v.intro] ? html`<span>${INTRO_SUB[v.intro]}</span>` : ''}</div>
          <button class="btn ghost intro-skip" data-act="skip-intro" data-k="skip-intro">Skip</button>` : ''}
        ${v.boss ? html`<div class="bars" aria-hidden="true"></div>` : ''}
      </div>
      ${cardOn ? html`<div class="pad stack enc-goal" style="gap:10px">
        <section class="card goal-card"><div class="story-banner small">${v.goal === 'befriend' ? 'Befriend' : 'Restore'}</div>
          <h2 class="h-sec" style="margin:8px 0 0">${C.name}${v.boss ? '' : ' appeared'}</h2>
          <div class="row" style="justify-content:center;gap:4px;margin-top:4px;flex-wrap:wrap">${kindTag(C)}${affinityTag(C.affinity)}</div>
          <p class="body" style="margin:8px 0 0">${v.goal === 'befriend' ? `Goal: fill its Calm meter. Take turns using abilities, items or a moment of quiet. ${C.name} may skitter, but nothing here can hurt your Evochi.` : `Goal: bring its Instability to zero. Lumen Glow works best against the Hollow. It may lash out and tire ${pet?.name || 'your Evochi'}, but never worse than that.`}</p>
          <div class="kv card inset" style="padding:8px 12px;margin-top:8px;text-align:left"><span>Recommended</span><b>${v.recommended.items.map((i) => ITEMS[i].name).join(', ')}${v.recommended.stage > 1 ? ` · ${stageLabel(v.recommended.stage)}+` : ''}</b>
            <span>You have</span><b>${items.length ? items.slice(0, 3).map((i) => `${i.name}${i.qty > 1 ? ' x' + i.qty : ''}`).join(', ') : 'no useful items (that’s fine)'}</b></div>
          <button class="btn green block" style="margin-top:10px" data-act="begin" data-autofocus data-k="begin">Begin</button>
          <button class="btn cream block" data-act="retreat-confirm" data-k="g-retreat">Not yet: retreat</button></section></div>` : ''}
      ${phase === 'play' ? html`<div class="enc-panel">
        <section class="speech enc-log" aria-live="polite"><i class="tail" style="left:${(wildPos[0] / sc.w) * 100}%" aria-hidden="true"></i>
          ${prevLog && prevLog.who === 'you' ? html`<div class="tiny muted you-line">${prevLog.text}</div>` : ''}
          <p class="line">${lastLog.text}</p>
          <div class="tiny muted" style="margin-top:4px">Turn ${v.turn + 1}${v.phase2 ? ' · The Sentinel is waking' : ''}</div></section>
        <div class="enc-actions">
          ${v.actions.map((a) => html`<button class="enc-act ${a.kind}" data-act="do" data-arg="${a.id}" data-k="act-${a.id}" ${a.can ? '' : raw('disabled')} aria-label="${a.name}: ${a.text}${a.energy > 0 ? `, costs ${a.energy} Energy` : a.energy < 0 ? `, restores ${-a.energy} Energy` : ''}">
            <img src="${icon(a.icon)}" alt="">
            <b>${a.name}</b>
            <span class="fx">${a.kind === 'item' ? `${items.length} usable` : a.kind === 'restore' ? `+${-a.energy} Energy · +${a.power}` : a.kind === 'companion' ? (v.companionUsed ? 'Used' : `+${a.power} · free`) : `+${a.power} · ${a.energy} Energy`}</span></button>`)}
        </div>
        <button class="btn ghost block" data-act="retreat-confirm" data-k="retreat" style="margin-top:2px">Retreat</button>
      </div>` : ''}
      ${outroOn ? html`<div class="pad stack enc-goal" style="gap:10px"><section class="card goal-card outro">
        <h2 class="h-sec" style="margin:0">${v.goal === 'befriend' ? `${C.name} trusts you.` : 'The Hollow lifts.'}</h2>
        <p class="body" style="margin:6px 0 0">${lastLog.text}</p></section></div>` : ''}
      ${resultOn ? resultCard(ctx, v) : ''}
    </main>`;
  },
  actions: {
    'skip-intro'(ctx) {
      const u = ctx.ui('encounter');
      if (u.introTimer) clearTimeout(u.introTimer);
      u.introTimer = null;
      u.phase = 'card';
      ctx.rerender();
    },
    begin(ctx) {
      ctx.ui('encounter').phase = 'play';
      ctx.sfx('ui_tap', 0.4);
      ctx.rerender();
    },
    do(ctx, actionId) {
      if (actionId === 'item') return openItemPicker(ctx);
      runAction(ctx, actionId, null);
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
              c.ui('encounter').phase = null;
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
      ctx.ui('encounter').phase = null;
      ctx.go('guild', {}, { replace: true });
      openStoryReward(ctx, qid, { then: 'stay' });
    },
  },
};

function runAction(ctx, actionId, itemId) {
  const before = ctx.d.trails.encounter;
  const r = ctx.act(TR.encounterAct, actionId, itemId);
  if (r.error) return;
  const u = ctx.ui('encounter');
  const after = TR.encounterView(ctx.store.state, ctx.now);
  const A = TR.ACTIONS[actionId];
  u.lastYou = A.kind;
  const turnEv = r.events.find((e) => e.type === 'encounter_turn');
  u.floatYou = turnEv ? turnEv.you : Math.round(Math.abs((after.goal === 'befriend' ? after.meter - before.meter : before.meter - after.meter)));
  u.floatWild = turnEv ? turnEv.wild : 0;
  u.lastWild = turnEv ? { energy: after.energy < before.energy - (A.energy > 0 ? A.energy : 0) } : null;
  u.wildHit = true;
  ctx.sfx(A.kind === 'light' ? 'reward_chime' : A.kind === 'restore' ? 'pet_chirp' : 'ui_tap', 0.5);
  if (after.done === 'success') ctx.sfx('evolve_fanfare');
  setTimeout(() => {
    u.floatYou = 0;
    u.floatWild = 0;
    u.wildHit = false;
    u.lastYou = null;
    ctx.rerender();
  }, 1300);
}

function openItemPicker(ctx) {
  ctx.modal({
    label: 'Use an item',
    render: (c) => {
      const v = c.d.trails.encounter;
      return html`<div class="stack">
        <h2 class="h-sec">Offer something</h2>
        ${v.items.length ? html`<div class="list">${v.items.map((it) => html`<button class="card row item-pick" data-act="pick" data-arg="${it.id}" data-k="pick-${it.id}"><img src="${itemImg(it.id)}" alt="" width="48" height="48"><div class="grow" style="text-align:left"><b class="h-card">${it.name} <span class="tag small cream">x${it.qty}</span></b><div class="small muted">+${it.amount} ${v.meterLabel}${it.liked ? html` · <b style="color:var(--gold-900)">${v.creature.name} loves this</b>` : ''}</div></div></button>`)}</div>`
          : html`<p class="body" style="margin:0">Nothing in your Bag helps here yet. Homemade food calms wild Evochi; tonics and Glowleaf steady the Hollow.</p>`}
        <button class="btn cream block" data-act="modal-close">Back</button></div>`;
    },
    actions: {
      pick: (c, id) => {
        c.closeModal();
        runAction(c, 'item', id);
      },
    },
  });
}

function resultCard(ctx, v) {
  const C = v.creature;
  const q = Q.QUESTS[v.quest];
  const r = q.rewards;
  return html`<div class="pad stack enc-goal" style="gap:10px"><section class="card goal-card result">
    <div class="story-banner">${v.goal === 'befriend' ? `You befriended ${C.name}!` : `${C.name} restored!`}</div>
    <div class="result-pic">${creatureImg(C.id, C.states.done, C.size === 'large' ? 140 : 120)}</div>
    <p class="body" style="margin:6px 0 0">${v.goal === 'befriend' ? `${C.name} joins your journey as a companion. It will visit your nest and help in encounters.` : `Its light is back. ${v.boss ? 'The third trail on the Waystone’s map glows again.' : 'The ruins feel brighter already.'}`}</p>
    <div class="row" style="justify-content:center;gap:6px;flex-wrap:wrap;margin-top:8px">
      ${r.coins ? html`<span class="tag stage" style="height:32px"><img src="${icon('coin')}" alt="" style="width:22px;height:22px">+${r.coins}</span>` : ''}
      ${Object.entries(r.gifts || {}).map(([id, n]) => html`<span class="tag cream" style="height:32px"><img src="${itemImg(id)}" alt="" style="width:24px;height:24px">${n} × ${ITEMS[id].name}</span>`)}
      ${(r.items || []).map((id) => html`<span class="tag cream" style="height:32px"><img src="${itemImg(id)}" alt="" style="width:24px;height:24px">${ITEMS[id].name}</span>`)}
      ${(r.titles || []).map((t) => html`<span class="tag ok" style="height:32px"><img src="${icon('crown')}" alt="" style="width:22px;height:22px">${Q.TITLES[t].name}</span>`)}</div>
    <div class="tiny muted" style="margin-top:6px">${v.turn} turn${v.turn === 1 ? '' : 's'}${Object.keys(v.used).length ? ' · items: ' + Object.entries(v.used).map(([id, n]) => `${ITEMS[id].name}${n > 1 ? ' x' + n : ''}`).join(', ') : ''}</div>
    <button class="btn green block" style="margin-top:10px" data-act="finish" data-autofocus data-k="finish">Continue</button></section></div>`;
}
