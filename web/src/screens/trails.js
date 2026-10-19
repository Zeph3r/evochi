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
      <img src="${ITEMS[d.icon] || Q.QUEST_MATERIALS[d.icon] ? itemImg(d.icon) : icon(d.icon)}" alt="">
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

// encounter prep and the encounter itself live in encounter.js
export { prep, encounter } from './encounter.js';

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
      <div class="travel-motes ${E.goal === 'befriend' ? 'wild' : 'hollow'}" aria-hidden="true">${Array.from({ length: 18 }, (_, i) => html`<i style="--i:${i};--x:${6 + ((i * 37) % 88)}%;--s:${0.6 + ((i * 7) % 5) / 6}"></i>`)}</div>
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
