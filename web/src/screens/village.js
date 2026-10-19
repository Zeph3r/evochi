// Village Tales, Chapter 1: Sunlit Village Square, the three interiors, the Waystone, villager dialogue,
// story quest details and the reward card (Quest Bible §8). No sixth tab: the Village opens from Home,
// story quests live in Journey > Story, quest items in Bag > Quest Pouch.
import * as G from '../game/state.js';
import * as Q from '../game/story.js';
import * as H from '../game/home.js';
import * as TR from '../game/trails.js';
import { clueGlint, discoveryActions } from './trails.js';
import { ITEMS, STORY_SOURCE, DECOR_SLOTS } from '../game/catalog.js';
import { html, raw, fmt } from '../ui/dom.js';
import { icon, itemImg, url, manifest } from '../ui/assets.js';
import { ICON } from '../ui/icons.js';
import { coinPill } from '../core/app.js';
import { puppetHTML, startPuppets, setPuppetState, flatSprite } from '../ui/puppet.js';

const NPC_KEY = (id) => id.replace('npc_', '');
const SPEAKER = {
  npc_mira: { name: 'Mira', role: 'the Gardener', col: '#5E7F4A' },
  npc_bram: { name: 'Bram', role: 'the Lanternkeeper', col: '#8D5D3B' },
  npc_pip: { name: 'Pip', role: 'the Courier', col: '#AD652F' },
  npc_alder: { name: 'Alder', role: 'the Mapmaker', col: '#43523D' },
  waystone: { name: 'The Waystone', role: '', col: '#6E8A7E' },
};
const UNLOCK_ICON = { Cottage: 'home_map', Kitchen: 'skill_cooking', Apothecary: 'skill_alchemy' };
export function questLead(v) {
  if (v.line === 'home') return `Home Tales · Quest ${String(v.n).padStart(2, '0')}`;
  if (v.line === 'trail') return `Lumen Trails · Trail job ${String(v.n).padStart(2, '0')}`;
  if (v.line === 'side') return 'Side story · optional';
  return `${Q.CHAPTER.name} · Quest ${String(v.n).padStart(2, '0')}`;
}
const PLACE_ICON = { glasshouse: 'care', workshop: 'bell', lodge: 'mail', waystone: 'star' };

function V() {
  return manifest().village;
}
export function npcSprite(npcId, expr = 'neutral') {
  return flatSprite(V().npcs[NPC_KEY(npcId)], expr);
}
function squareArt(flags) {
  const sq = V().square;
  return url(flags.waystone_restored ? sq.waystone_restored : flags.lamp_lit ? sq.lamp_lit : sq.day_dim);
}
export function storyItemImg(id) {
  return itemImg(id);
}
function npcName(id) {
  return id === 'waystone' ? 'the Waystone' : id === 'cottage' ? 'your Cottage' : id === 'ruins' || id === 'gate' ? TR.PLACE_NAMES[id] : SPEAKER[id].name;
}

/** "Grow 3 Sunberries (1/3)" for the items still missing from a hand-in. */
function gatherText(needs) {
  return needs.filter((x) => !x.ok).map((x) => {
    const src = H.homeSource(x.id);
    return `${src ? src.verb : 'Find'} ${x.need} ${H.itemLabel(x.id, x.need)} (${x.have}/${x.need})`;
  }).join(', ');
}

/** Where the quest card's main button should take the player. */
function questGo(v) {
  const n = v.next;
  if (n.kind === 'walk') return { act: 'sq-walk', label: 'Go for a walk', cls: 'green' };
  if (n.kind === 'gather') {
    const miss = n.needs.find((x) => !x.ok);
    const src = H.homeSource(miss.id);
    if (src) return { act: 'sq-home', arg: src.route === 'station' ? src.station : 'garden', label: `Go to your ${src.place}`, cls: 'green' };
  }
  if (n.kind === 'grow') return { act: 'sq-pet', label: 'Check on your Evochi', cls: 'cream' };
  if (n.kind === 'encounter' || (n.encounter && n.kind === 'gather')) return { act: 'sq-prep', arg: v.id, label: n.kind === 'encounter' ? 'Prepare & Travel' : 'Encounter prep', cls: n.kind === 'encounter' ? 'green' : '' };
  if (n.place === 'cottage') return { act: 'sq-home', arg: 'cottage', label: 'Go to your Cottage' };
  if (v.phase === 'locked' && v.lock?.needSkills && Object.keys(v.lock.needSkills).length) return { act: 'sq-home', arg: 'skills', label: 'Open Skills', cls: 'cream' };
  if (n.kind === 'talk' || n.kind === 'handin' || n.kind === 'locked' || n.kind === 'gather' || n.kind === 'grow') {
    return { act: 'sq-go', arg: n.place, label: `Go to ${n.place && Q.PLACES[n.place] ? Q.PLACES[n.place].name : 'the Village'}` };
  }
  return null;
}

/** One line for "what to do next" on a quest. */
export function nextText(v) {
  const n = v.next;
  if (v.completed) return 'Complete';
  if (v.phase === 'locked') return v.lock?.text || 'Locked';
  if (n.kind === 'talk') return `Talk to ${npcName(n.npc)} in ${Q.PLACES[n.place].name}`;
  if (n.kind === 'walk') {
    if (v.paused) return 'Waiting for steps: connect a step source to keep going';
    if (v.walk.type === 'incremental') return `Walk ${fmt(v.resolved - (v.walk.progress || 0))} more steps`;
    return v.walk.todayDone ? `Day ${v.walk.qualified}/${v.walk.days} done. Walk again tomorrow`
      : `Walk ${fmt(v.resolved)} steps today (day ${v.walk.qualified + 1} of ${v.walk.days})`;
  }
  if (n.kind === 'encounter') return `Travel to ${TR.PLACE_NAMES[n.place]}: ${n.label.toLowerCase()}`;
  if (n.kind === 'gather') return gatherText(n.needs);
  if (n.kind === 'grow') return `Visit once your Evochi has grown into a ${['', 'Eggling', 'Juvenile', 'Elder'][n.stage]}`;
  if (n.kind === 'handin') {
    if (n.npc === 'waystone') return 'Restore the Waystone in the Square';
    if (n.npc === 'cottage') return 'Restore the Cottage on your Home Map';
    if (/ to /.test(n.label)) return n.label;
    return /^(Give|Bring|Hand)/.test(n.label) ? `${n.label} to ${npcName(n.npc)}` : n.label;
  }
  return '';
}

export function statusTag(v) {
  if (v.completed) return html`<span class="tag ok">${ICON.checkDark}Complete</span>`;
  if (v.phase === 'locked') return html`<span class="tag neutral"><img src="${icon('lock')}" alt="">Lv ${v.level}</span>`;
  if (v.phase === 'available') return html`<span class="tag stage">New</span>`;
  if (v.next.kind === 'handin' || v.next.kind === 'encounter') return html`<span class="tag ok">Ready</span>`;
  if (v.next.kind === 'grow') return html`<span class="tag warn">Needs a Juvenile</span>`;
  if (v.paused) return html`<span class="tag warn">Paused</span>`;
  return html`<span class="tag cream">In progress</span>`;
}

export function walkBar(v) {
  if (!v.accepted || v.completed) return '';
  if (!v.walk || v.next.kind !== 'walk') {
    // item objectives (harvests, homemade food): one small counter per item still needed
    const its = v.objectives.filter((o) => o.item && !o.done);
    if (!its.length) return '';
    return html`<div class="item-goals">${its.map((o) => html`<span class="item-goal ${o.ready ? 'ok' : ''}"><img src="${itemImg(o.item)}" alt="">
      <span class="bar ${o.ready ? 'green' : 'amber'}" aria-hidden="true"><i style="width:${(o.have / o.need) * 100}%"></i></span><b>${o.have}/${o.need}</b><span class="sr-only">${ITEMS[o.item].name}</span></span>`)}</div>`;
  }
  if (v.walk.type === 'incremental') {
    const p = Math.min(1, (v.walk.progress || 0) / v.resolved);
    return html`<div class="bar green" role="progressbar" aria-label="Story walk" aria-valuemin="0" aria-valuemax="${v.resolved}" aria-valuenow="${v.walk.progress || 0}"><i style="width:${p * 100}%"></i></div>
      <div class="tiny muted" style="margin-top:3px">${fmt(v.walk.progress || 0)} / ${fmt(v.resolved)} new steps</div>`;
  }
  const dots = Array.from({ length: v.walk.days }, (_, i) => i < v.walk.qualified);
  const tp = Math.min(1, (v.walk.todaySteps || 0) / v.resolved);
  return html`<div class="story-days" aria-label="${v.walk.qualified} of ${v.walk.days} walking days">${dots.map((on, i) => html`<span class="${on ? 'on' : ''}">${on ? ICON.check : i + 1}</span>`)}</div>
    ${v.walk.qualified < v.walk.days ? html`<div class="bar green" aria-hidden="true" style="margin-top:6px"><i style="width:${(v.walk.todayDone ? 1 : tp) * 100}%"></i></div>
      <div class="tiny muted" style="margin-top:3px">Today: ${fmt(v.walk.todayDone ? v.resolved : v.walk.todaySteps || 0)} / ${fmt(v.resolved)} steps${v.walk.todayDone ? ' ✓' : ''}</div>` : ''}`;
}

function rewardChips(r) {
  return html`${(r.items || []).map((id) => html`<span class="reward-chip story"><img src="${itemImg(id)}" alt=""><span>${ITEMS[id].name}</span></span>`)}
    ${r.coins ? html`<span class="reward-chip"><img src="${icon('coin')}" alt=""><span>${r.coins}</span></span>` : ''}
    ${Object.entries(r.gifts || {}).map(([id, n]) => html`<span class="reward-chip"><img src="${itemImg(id)}" alt=""><span>${n} × ${ITEMS[id].name}</span></span>`)}
    ${r.companion ? html`<span class="reward-chip story"><img src="${icon('creature_' + r.companion)}" alt=""><span>${TR.CREATURES[r.companion].name} joins you</span></span>` : ''}
    ${(r.unlocks || []).map((u) => html`<span class="reward-chip unlock"><img src="${icon(UNLOCK_ICON[u] || 'star')}" alt=""><span>Unlocks ${u}</span></span>`)}
    ${(r.titles || []).map((t) => html`<span class="reward-chip"><img src="${icon('crown')}" alt=""><span>Title: ${Q.TITLES[t].name}</span></span>`)}`;
}

// ------------------------------------------------------------------ quest details (modal)
export function openStoryQuest(ctx, qid) {
  ctx.act(Q.markOfferSeen, qid);
  ctx.modal({
    label: Q.QUESTS[qid].title,
    render: (c) => {
      const v = Q.questView(c.state, qid, c.now);
      const g = v.completed ? null : questGo(v);
      const go = g ? html`<button class="btn ${g.cls || ''} block" data-act="${g.act}" data-arg="${g.arg || ''}" data-k="sq-go">${g.label}</button>` : '';
      return html`<div class="stack story-modal">
        <div class="row" style="gap:10px"><img src="${npcSprite(Q.QUESTS[qid].giver, v.completed ? 'happy' : 'neutral')}" alt="" class="story-face">
          <div class="grow"><div class="tiny muted">${questLead(v)}</div>
            <h2 class="h-sec">${v.title}</h2>
            <div class="row" style="gap:6px;margin-top:4px;flex-wrap:wrap"><span class="tag small cream">Lv ${v.level}+</span>${statusTag(v)}</div></div></div>
        <p class="body" style="margin:0">${v.summary}</p>
        ${v.paused ? html`<div class="status-banner sync" role="status"><img src="${icon('steps')}" alt=""><span class="grow">Step sync is off, so this walk is paused. Your progress is saved and nothing expires.</span></div>` : ''}
        ${v.accepted && !v.completed ? html`<div class="card inset" style="padding:10px"><b class="small">Next: ${nextText(v)}</b><div style="margin-top:6px">${walkBar(v)}</div></div>` : ''}
        <ol class="objectives">${v.objectives.map((o) => html`<li class="${o.done ? 'done' : o.id === v.current && v.accepted ? 'now' : ''} ${o.optional ? 'optional' : ''}"><span class="ck" aria-hidden="true">${o.done || (o.optional && o.ready) ? ICON.check : ''}</span><span>${o.text}</span>${o.done ? html`<span class="sr-only">(done)</span>` : ''}</li>`)}</ol>
        <div><div class="small" style="font-weight:800;margin-bottom:6px">Rewards</div><div class="row" style="flex-wrap:wrap;gap:6px">${rewardChips(v.rewards)}</div>
          <p class="tiny muted" style="margin:6px 0 0">Story rewards are earned, never sold: they can't be bought, traded or sold.</p></div>
        ${v.accepted && !v.completed ? html`<label class="row between track-row"><span class="small" style="font-weight:800">Track on Home</span>
          <button class="switch" role="switch" aria-checked="${v.tracked}" data-act="sq-track" data-k="sq-track" aria-label="Track this quest"></button></label>` : ''}
        ${go}
        <button class="btn cream block" data-act="modal-close" data-k="sq-close">Close</button></div>`;
    },
    actions: {
      'sq-go': (c, place) => {
        c.closeModal();
        const n = Q.questView(c.state, qid, c.now).next;
        if (place && Q.PLACES[place]) c.go('place', { id: place, npc: n.npc && n.npc !== 'waystone' ? n.npc : undefined });
        else c.go('village');
      },
      'sq-home': (c, where) => {
        c.closeModal();
        if (where === 'kitchen' || where === 'apothecary') c.go('station', { id: where });
        else c.go(where);
      },
      'sq-pet': (c) => {
        c.closeModal();
        c.go('inspect');
      },
      'sq-prep': (c, id) => {
        c.closeModal();
        c.go('prep', { id });
      },
      'sq-walk': (c) => {
        c.closeModal();
        c.app.ui.journey = { ...(c.app.ui.journey || {}), tab: 'daily' };
        c.app.tab('journey');
      },
      'sq-track': (c) => {
        const v = Q.questView(c.state, qid, c.now);
        c.act(Q.setTracked, qid, !v.tracked);
        c.app.renderModals();
      },
    },
  });
}

// ------------------------------------------------------------------ reward card (modal)
export function openStoryReward(ctx, qid, { then = 'village' } = {}) {
  const q = Q.QUESTS[qid];
  ctx.act(Q.markCompletionSeen, qid);
  ctx.sfx('reward_chime');
  ctx.modal({
    center: true,
    label: 'Quest complete',
    noDismiss: true,
    render: (c) => {
      const r = q.rewards;
      const id = (r.items || [])[0];
      if (!id) return homeRewardCard(c, q, then);
      const it = ITEMS[id];
      const s = c.state;
      const equipped = it.category === 'wearable' && s.pet?.equipped?.[it.slot] === id;
      const placed = it.category === 'decoration' && Object.values(s.nest.placements).includes(id);
      return html`<div class="stack center story-reward">
        <div class="story-banner">Quest complete!</div>
        <div class="tiny muted">${questLead(Q.questView(c.state, qid, c.now))}</div>
        <h2 class="h-sec" style="margin:0">${q.title}</h2>
        <div class="reward-card">
          <span class="story-tag">${raw(starSvg())}Story reward</span>
          <img src="${itemImg(id)}" alt="" width="132" height="132">
          <b class="h-card">${it.name}</b>
          <p class="small" style="margin:4px 0 0;color:var(--ink-700)">${it.desc}</p>
        </div>
        <div class="row" style="justify-content:center;gap:8px;flex-wrap:wrap">
          <span class="tag stage" style="height:34px;font-size:16px"><img src="${icon('coin')}" alt="" style="width:24px;height:24px">+${r.coins}</span>
          ${(r.titles || []).map((t) => html`<span class="tag ok" style="height:34px;font-size:15px"><img src="${icon('crown')}" alt="" style="width:24px;height:24px">Title: ${Q.TITLES[t].name}</span>`)}
        </div>
        ${it.category === 'wearable'
          ? html`<button class="btn block" data-act="sr-equip" ${equipped || !s.pet ? raw('disabled') : ''} data-autofocus>${equipped ? 'Equipped' : 'Equip now'}</button>`
          : html`<button class="btn block" data-act="sr-place" ${placed ? raw('disabled') : ''} data-autofocus>${placed ? 'Placed in your Nest' : 'Place in Nest'}</button>`}
        <button class="btn cream block" data-act="sr-done">${then === 'village' ? 'Back to Village' : 'Done'}</button></div>`;
    },
    actions: {
      'sr-equip': (c) => {
        const id = q.rewards.items[0];
        const r = c.act(G.equip, id);
        if (!r.error) {
          c.sfx('reward_chime', 0.5);
          c.toast(`${ITEMS[id].name} equipped`, 'ok', 'wearables');
        }
        c.app.renderModals();
      },
      'sr-place': (c) => {
        const id = q.rewards.items[0];
        const it = ITEMS[id];
        const slots = Object.entries(DECOR_SLOTS).filter(([, sl]) => sl.accepts.includes(it.decor));
        const target = slots.find(([sid]) => !c.state.nest.placements[sid]) || slots[0];
        const r = c.act(G.placeDecoration, id, target[0]);
        if (!r.error) {
          c.sfx('ui_tap');
          c.toast(`${it.name} placed in the ${DECOR_SLOTS[target[0]].label.toLowerCase()} spot`, 'ok', 'decorations');
        }
        c.app.renderModals();
      },
      'sr-done': (c) => {
        c.closeModal();
        if (then === 'village') c.go('village');
      },
      'sr-home': (c, where) => {
        c.closeModal();
        if (where === 'kitchen' || where === 'apothecary') c.go('station', { id: where });
        else c.go(where);
      },
    },
  });
}

/** Reward card for quests that pay out gifts, unlocks and titles instead of one story item. */
function homeRewardCard(c, q, then) {
  const r = q.rewards;
  const gifts = Object.entries(r.gifts || {});
  const room = (r.unlocks || []).includes('Apothecary') ? 'apothecary' : (r.unlocks || []).includes('Kitchen') ? 'kitchen' : null;
  return html`<div class="stack center story-reward">
    <div class="story-banner">Quest complete!</div>
    <div class="tiny muted">${questLead(Q.questView(c.state, q.id, c.now))}</div>
    <h2 class="h-sec" style="margin:0">${q.title}</h2>
    ${r.companion ? html`<div class="reward-card unlocks"><span class="story-tag">${raw(starSvg())}New companion</span>
      <div class="row" style="justify-content:center;gap:14px;flex-wrap:wrap"><span class="unlock-big"><img src="${icon('creature_' + r.companion)}" alt="" width="96" height="96"><b class="h-card">${TR.CREATURES[r.companion].name}</b></span></div></div>`
      : (r.unlocks || []).length ? html`<div class="reward-card unlocks"><span class="story-tag">${raw(starSvg())}Unlocked</span>
      <div class="row" style="justify-content:center;gap:14px;flex-wrap:wrap">${r.unlocks.map((u) => html`<span class="unlock-big"><img src="${icon(UNLOCK_ICON[u] || 'star')}" alt="" width="74" height="74"><b class="h-card">${u}</b></span>`)}</div></div>` : ''}
    <div class="row" style="justify-content:center;gap:8px;flex-wrap:wrap">
      ${r.coins ? html`<span class="tag stage" style="height:34px;font-size:16px"><img src="${icon('coin')}" alt="" style="width:24px;height:24px">+${r.coins}</span>` : ''}
      ${gifts.map(([id, n]) => html`<span class="tag cream" style="height:34px;font-size:14px"><img src="${itemImg(id)}" alt="" style="width:26px;height:26px">${n} × ${ITEMS[id].name}</span>`)}
      ${(r.titles || []).map((t) => html`<span class="tag ok" style="height:34px;font-size:15px"><img src="${icon('crown')}" alt="" style="width:24px;height:24px">Title: ${Q.TITLES[t].name}</span>`)}
    </div>
    ${room ? html`<button class="btn block" data-act="sr-home" data-arg="${room}" data-autofocus>Open your ${room === 'kitchen' ? 'Kitchen' : 'Apothecary'}</button>` : ''}
    <button class="btn ${room ? 'cream' : ''} block" data-act="sr-done" ${room ? '' : raw('data-autofocus')}>${then === 'village' ? 'Back to Village' : 'Done'}</button></div>`;
}

function starSvg() {
  return '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.5l2.9 6 6.6.8-4.9 4.5 1.3 6.5L12 17l-5.9 3.3 1.3-6.5L2.5 9.3l6.6-.8z" fill="#F4B84E" stroke="#80531F" stroke-width="1.4" stroke-linejoin="round"/></svg>';
}

// ------------------------------------------------------------------ the Square
const PINS = [
  { id: 'lodge', label: 'Trail Guild', npcs: ['npc_pip', 'npc_alder'] },
  { id: 'glasshouse', label: 'Glasshouse', npcs: ['npc_mira'] },
  { id: 'workshop', label: 'Workshop', npcs: ['npc_bram'] },
  { id: 'waystone', label: 'Waystone', npcs: ['waystone'] },
];

function placeState(ctx, id) {
  const st = ctx.d.story;
  const marks = Q.npcMarkers(ctx.state, ctx.now);
  const p = PINS.find((x) => x.id === id);
  const mark = p.npcs.map((n) => marks[n]).find(Boolean) || null;
  let lock = null;
  if (id === 'lodge') {
    const v = st.quests.find((x) => x.id === 'vq02');
    if (v.phase === 'locked') lock = v.lock.needLevel ? `Quests from Lv ${v.level}` : 'Quests later';
  }
  if (id === 'waystone' && !st.flags.waystone_revealed) lock = 'A sleeping stone';
  return { mark, lock };
}

export const village = {
  id: 'village',
  scene: () => null,
  render(ctx) {
    const st = ctx.d.story;
    const sq = V().square;
    const nu = st.nextUp;
    return html`<main class="screen scroll paper village" aria-label="Sunlit Village">
      <header class="hud vhud"><button class="back-btn" data-act="back" aria-label="Back to your nest" data-k="vback">${ICON.back}</button>
        <h1 class="place-title"><span class="full">Sunlit Village</span><span class="short" aria-hidden="true">Village</span></h1>${coinPill(ctx)}</header>
      <div class="village-map" style="aspect-ratio:${sq.w} / ${sq.h}">
        <img class="plate" src="${squareArt(st.flags)}" alt="Sunlit Village Square: Mira's Glasshouse on the left, Bram's Workshop on the right, the Trail Guild Lodge up the road and the Waystone in the middle${st.flags.lamp_lit ? '. The nursery lamp is lit.' : '.'}">
        ${PINS.map((p) => {
          const a = sq.anchors[p.id];
          const { mark, lock } = placeState(ctx, p.id);
          return html`<button class="pin ${mark ? 'has-' + mark : ''} ${lock ? 'locked' : ''}" data-act="place" data-arg="${p.id}" data-k="pin-${p.id}"
            style="left:${(a[0] / sq.w) * 100}%;top:${(a[1] / sq.h) * 100}%" aria-label="${Q.PLACES[p.id].name}${mark === 'handin' ? ', something to hand in' : mark === 'quest' ? ', new quest' : ''}${lock ? `, ${lock}` : ''}">
            ${mark ? html`<i class="pin-mark" aria-hidden="true">${mark === 'handin' ? raw(ICON.checkDark) : '!'}</i>` : ''}<span>${p.label}</span>${lock ? html`<small><img src="${icon('lock')}" alt="">${lock}</small>` : ''}</button>`;
        })}
      </div>
      <div class="pad stack" style="gap:10px;margin-top:-14px;position:relative;z-index:3;padding-bottom:calc(20px + var(--safe-bottom))">
        ${nu ? html`<button class="card story-strip" data-act="quest" data-arg="${nu.id}" data-k="vstrip">
          <img class="face" src="${npcSprite(Q.QUESTS[nu.id].giver, nu.next.kind === 'handin' ? 'happy' : 'neutral')}" alt="">
          <div class="grow" style="min-width:0;text-align:left"><div class="tiny muted">${nu.accepted ? 'Current story' : nu.phase === 'locked' ? 'Coming up' : 'New story'}</div>
            <b class="h-card">${nu.title}</b><div class="small" style="color:var(--ink-700)">${nextText(nu)}</div>
            ${nu.accepted ? html`<div style="margin-top:6px">${walkBar(nu)}</div>` : ''}</div>
          <span class="chev" aria-hidden="true">&rsaquo;</span></button>`
        : html`<div class="card story-strip done"><img src="${icon('star')}" alt="" width="44" height="44"><div class="grow"><b class="h-card">Chapter 1 complete</b><div class="small" style="color:var(--ink-700)">Every path has a little light again. More Village Tales are on the way.</div></div></div>`}
        <h2 class="h-sec sec-head">Places</h2>
        <div class="place-grid">
          ${PINS.map((p) => {
            const { mark, lock } = placeState(ctx, p.id);
            const P = Q.PLACES[p.id];
            const thumb = p.id === 'waystone' ? url(st.flags.waystone_restored ? V().waystone.restored : V().waystone.dormant) : url(V().places[p.id].file);
            return html`<button class="place-card" data-act="place" data-arg="${p.id}" data-k="pc-${p.id}">
              <img src="${thumb}" alt=""><span class="nm"><img src="${icon(PLACE_ICON[p.id])}" alt="">${P.name}</span>
              <span class="ds">${lock || P.blurb}</span>${mark ? html`<i class="badge-dot" aria-hidden="true"></i>` : ''}</button>`;
          })}
        </div>
        <button class="card row market-row" data-act="guild" data-k="vguild"><img src="${icon('trail_badge')}" alt="" width="40" height="40"><div class="grow" style="text-align:left"><b class="h-card">Trail Guild Board</b><div class="small muted">${guildBlurb(ctx)}</div></div>${guildDot(ctx)}<span class="chev" aria-hidden="true">&rsaquo;</span></button>
        ${trailPlaces(ctx)}
        <button class="card row market-row" data-act="market" data-k="vmarket"><img src="${icon('shop')}" alt="" width="40" height="40"><div class="grow" style="text-align:left"><b class="h-card">Evochi Market</b><div class="small muted">The village shop. Story rewards are never sold here.</div></div><span class="chev" aria-hidden="true">&rsaquo;</span></button>
      </div>
    </main>`;
  },
  actions: {
    ...discoveryActions,
    place(ctx, id) {
      ctx.sfx('ui_tap', 0.4);
      ctx.go('place', { id });
    },
    market(ctx) {
      ctx.app.tab('shop');
    },
    trailplace(ctx, id) {
      ctx.sfx('ui_tap', 0.4);
      ctx.go('trailplace', { id });
    },
  },
};

function guildBlurb(ctx) {
  const t = ctx.d.trails;
  if (!t) return 'Daily discoveries and trail jobs.';
  if (t.ready.length) return `${t.ready.length} discover${t.ready.length === 1 ? 'y' : 'ies'} ready to inspect`;
  const enc = ctx.d.story.encounters.length;
  if (enc) return 'A trail job is ready: prepare and travel';
  if (t.foundToday < 3) return `${3 - t.foundToday} discover${3 - t.foundToday === 1 ? 'y' : 'ies'} left today · ${t.rank.name}`;
  return `All found today · ${t.rank.name}`;
}
function guildDot(ctx) {
  const t = ctx.d.trails;
  return t && (t.ready.length || ctx.d.story.encounters.length || (t.foundToday === 0 && !t.walking.length)) ? html`<i class="badge-dot" aria-hidden="true" style="position:static;margin-right:4px"></i>` : '';
}
function trailPlaces(ctx) {
  const st = ctx.d.story;
  const out = [];
  const ruinsOpen = ['ruins_ready', 'completed'].includes(Q.questPhase(ctx.state, 'eq01'));
  const gateOpen = ['gate_ready', 'completed'].includes(Q.questPhase(ctx.state, 'eq03'));
  if (!ruinsOpen && !gateOpen) return '';
  const TMs = manifest().trails?.scenes;
  if (!TMs) return '';
  if (ruinsOpen) out.push(['ruins', 'Mossy Ruins', st.flags.sprout_restored ? 'Peaceful again. Petals on the arch.' : 'A quiet forest ruin on the old trail.', TMs.mossy_ruins.file]);
  if (gateOpen) out.push(['gate', 'The Old Gate', st.flags.sentinel_restored ? 'Open, and humming at dusk.' : 'Past the bridge. Hollow light in the dusk.', TMs.sentinel_gate.file]);
  return html`<h2 class="h-sec sec-head">Lumen Trails</h2><div class="place-grid">${out.map(([id, name, blurb, file]) => {
    const clue = TR.cluesAt(ctx.state, id, ctx.now).length;
    return html`<button class="place-card" data-act="trailplace" data-arg="${id}" data-k="pc-${id}"><img src="${url(file)}" alt="" style="object-position:50% 60%"><span class="nm"><img src="${icon('trail')}" alt="">${name}</span><span class="ds">${blurb}</span>${clue ? html`<i class="badge-dot" aria-hidden="true"></i>` : ''}</button>`;
  })}</div>`;
}

// ------------------------------------------------------------------ places + dialogue
function convoFor(ctx, npcId) {
  return Q.npcConversation(ctx.state, npcId, ctx.now);
}

function placeNpc(ctx) {
  const id = ctx.app.route.params.id;
  const P = Q.PLACES[id];
  const u = ctx.ui('place');
  if (u.place !== id || u.route !== ctx.app.route) {
    // every visit starts a fresh conversation (re-renders keep the same route object)
    u.route = ctx.app.route;
    u.place = id;
    u.npc = null;
    u.node = null;
  }
  if (id === 'waystone') return 'waystone';
  if (!u.npc || !P.npcs.includes(u.npc)) {
    const marks = Q.npcMarkers(ctx.state, ctx.now);
    u.npc = ctx.app.route.params.npc || P.npcs.find((n) => marks[n]) || P.npcs[0];
  }
  return u.npc;
}

function currentNode(ctx, npcId) {
  const u = ctx.ui('place');
  const c = convoFor(ctx, npcId);
  if (!u.node || u.convNpc !== npcId) {
    u.node = c.start;
    u.convNpc = npcId;
    u.extraNodes = c.nodes; // the opening graph stays reachable even if state changes mid-conversation
  }
  // a node from an earlier state (after an action) is kept until the player moves on
  const nodes = { ...(u.extraNodes || {}), ...c.nodes };
  if (!nodes[u.node]) u.node = c.start;
  return { node: nodes[u.node], nodes };
}

function handinIcons(ctx, ch) {
  if (!ch.act || ch.act.kind !== 'handin') return '';
  const t = Q.QUESTS[ch.act.quest].turnIns.find((x) => x.id === ch.act.turnIn);
  const items = [...Object.entries(t.consume || {}), ...Object.entries(t.consumeItems || {})];
  if (!items.length) return '';
  return html`<span class="give">${items.map(([id, n]) => html`<img src="${itemImg(id)}" alt="">${n > 1 ? html`<b>x${n}</b>` : ''}`)}</span>`;
}

const TYPE_MS = 24;          // per character: a line of ~80 characters types in about two seconds
let typing = null;

/** Where a villager is drawn on the room plate (percent of the stage), from the art's stage layout. */
function npcBox(m, pw, ph) {
  const st = m.stage || { gx: 0.36, gy: 0.8, hf: 0.5, flip: false };
  const h = st.hf * 100;
  const w = st.hf * (m.w / m.h) * (ph / pw) * 100;
  const gx = (st.flip ? m.w - m.ground[0] : m.ground[0]) / m.w;
  const gy = m.ground[1] / m.h;
  const tx = ((st.flip ? m.w - (m.top || m.ground)[0] : (m.top || m.ground)[0]) / m.w) * 100;
  const ty = ((m.top || [0, 0])[1] / m.h) * 100;
  return { left: st.gx * 100 - gx * w, top: st.gy * 100 - gy * h, w, h, gx: gx * 100, gy: gy * 100, tx, ty, flip: st.flip, feet: st.gx * 100 };
}

function lineKey(ctx, npc, nodeId) {
  return `${ctx.app.route.params.id}:${npc}:${nodeId}`;
}

export const place = {
  id: 'place',
  scene: () => null,
  mount(ctx, el) {
    const npc = placeNpc(ctx);
    if (npc !== 'waystone') ctx.store.state.story?.npcsMet?.[npc] || setTimeout(() => ctx.act(Q.markNpcMet, npc), 0);
    if (!el) return;
    startPuppets(el, (k) => V().npcs[k], { reduced: ctx.app.reducedMotion });
    // the line types in (once per line; re-renders pick up where it was)
    if (typing) clearInterval(typing);
    const sp = el.querySelector('.speech');
    const out = sp?.querySelector('.typed');
    if (!out) return;
    const u = ctx.ui('place');
    const full = out.dataset.full;
    const key = out.dataset.key;
    const finish = () => {
      if (typing) clearInterval(typing);
      typing = null;
      out.textContent = full;
      sp.classList.add('done');
      el.querySelector('.choices')?.classList.remove('wait');
      const pup = el.querySelector('.npc.talking .pup');
      if (pup && pup.dataset.state === 'talk') setPuppetState(pup, V().npcs[pup.dataset.npc], 'idle');
      u.typedKey = key;
      u.typedDone = true;
    };
    if (ctx.app.reducedMotion || (u.typedKey === key && u.typedDone)) {
      finish();
      return;
    }
    if (u.typedKey !== key) {
      u.typedKey = key;
      u.typedDone = false;
      u.typedStart = performance.now();
    }
    u.finishLine = finish;
    const step = () => {
      const n = Math.floor((performance.now() - u.typedStart) / TYPE_MS);
      if (n >= full.length || !out.isConnected) return finish();
      out.textContent = full.slice(0, n);
    };
    step();
    typing = setInterval(step, TYPE_MS);
  },
  render(ctx) {
    const id = ctx.app.route.params.id;
    const P = Q.PLACES[id];
    const st = ctx.d.story;
    const npc = placeNpc(ctx);
    const { node } = currentNode(ctx, npc);
    const L = Q.LINES[node.id];
    const speaker = L.s;
    const sp = SPEAKER[speaker] || SPEAKER.waystone;
    const text = Q.lineText(ctx.state, node.id, ctx.now, ctx.state.pet?.name);
    const u = ctx.ui('place');
    const isWay = id === 'waystone';
    const art = isWay ? url(st.flags.waystone_restored || u.flare === 'restore' ? V().waystone.restored : V().waystone.dormant) : url(V().places[id].file);
    const pw = isWay ? V().waystone.w : V().places[id].w;
    const ph = isWay ? V().waystone.h : V().places[id].h;
    const npcs = isWay ? [] : P.npcs;
    const key = lineKey(ctx, npc, node.id);
    const typed = ctx.app.reducedMotion || (u.typedKey === key && u.typedDone);
    // a villager shown during another speaker's line (e.g. the Waystone finale) keeps their own sprite
    const exprFor = (n) => (speaker === n ? L.e || 'neutral' : 'neutral');
    const stateFor = (n) => (speaker === n ? (typed ? 'idle' : 'talk') : npcs.includes(speaker) ? 'listen' : 'idle');
    const marks = Q.npcMarkers(ctx.state, ctx.now);
    const activeQuest = st.quests.find((v) => v.accepted && !v.completed && (v.next.npc === npc || Q.QUESTS[v.id].giver === npc)) ||
      st.quests.find((v) => v.phase === 'available' && Q.QUESTS[v.id].giver === npc);
    const boxes = Object.fromEntries(npcs.map((n) => [n, npcBox(V().npcs[NPC_KEY(n)], pw, ph)]));
    const tailAt = boxes[speaker] ? Math.max(14, Math.min(86, boxes[speaker].feet)) : isWay ? 22 : 50;
    const single = node.choices.length === 1 && node.choices[0].next && !node.choices[0].act;
    const cameo = isWay && ['VQ03_MIR02', 'VQ03_BRA02', 'VQ03_PIP08', 'VQ03_ALD05'].includes(node.id);
    return html`<main class="screen scroll paper village place story" aria-label="${P.name}">
      <header class="hud vhud"><button class="back-btn" data-act="leave" aria-label="Back to the Square" data-k="pback">${ICON.back}</button>
        <h1 class="place-title"><span class="full">${P.name}</span><span class="short" aria-hidden="true">${P.short}</span></h1>${coinPill(ctx)}</header>
      <div class="stage-wrap ${isWay ? 'way' : ''}" style="--ar:${pw / ph}">
        <div class="stage place-plate ${u.flare ? 'flare' : ''} ${isWay ? 'way' : ''}" style="aspect-ratio:${pw} / ${ph}">
          <img class="plate" src="${art}" alt="">
          ${npcs.map((n) => {
            const m = V().npcs[NPC_KEY(n)];
            const b = boxes[n];
            const active = n === npc;
            const mark = marks[n];
            return html`<button class="npc ${active ? 'active' : ''} ${speaker === n ? 'talking' : ''} ${mark ? 'marked' : ''}" data-act="npc" data-arg="${n}" data-k="npc-${n}"
              style="left:${b.left.toFixed(2)}%;top:${b.top.toFixed(2)}%;width:${b.w.toFixed(2)}%;height:${b.h.toFixed(2)}%" aria-label="Talk to ${SPEAKER[n].name}${mark === 'handin' ? ', something to hand in' : mark ? ', new quest' : ''}" aria-pressed="${active}">
              <i class="tap-ring" style="left:${b.gx.toFixed(2)}%;top:${b.gy.toFixed(2)}%" aria-hidden="true"></i>
              <div class="fig ${b.flip ? 'flip' : ''}">${raw(puppetHTML(m, { key: NPC_KEY(n), expr: exprFor(n), state: stateFor(n) }))}</div>
              ${npcs.length > 1
                ? html`<span class="name-chip" style="left:${b.tx.toFixed(2)}%;top:${b.ty.toFixed(2)}%">${mark && !active ? html`<i class="quest-mark mini ${mark}" aria-hidden="true">${mark === 'handin' ? raw(ICON.checkDark) : '!'}</i>` : ''}${SPEAKER[n].name}</span>`
                : mark && !active ? html`<i class="quest-mark ${mark}" style="left:${b.tx.toFixed(2)}%;top:${b.ty.toFixed(2)}%" aria-hidden="true">${mark === 'handin' ? raw(ICON.checkDark) : '!'}</i>` : ''}
            </button>`;
          })}
          ${cameo ? html`<img class="npc-cameo" src="${npcSprite(speaker, L.e || 'happy')}" alt="">` : ''}
          ${clueGlint(ctx, id)}
        </div>
      </div>
      <section class="speech dialogue ${typed ? 'done' : ''}" aria-label="${sp.name}" data-act="speech" data-k="speech">
        <i class="tail" style="left:${tailAt}%" aria-hidden="true"></i>
        <div class="speech-top">
          <span class="speaker nametag" style="--sc:${sp.col}">${sp.name}${sp.role ? html` <small>${sp.role}</small>` : ''}</span>
          ${activeQuest ? html`<button class="btn sm cream" data-act="quest" data-arg="${activeQuest.id}" data-k="dq"><img src="${icon('journey')}" alt="">Quest</button>` : ''}
        </div>
        <p class="line" aria-live="polite"><span class="sr-only">${text}</span><span class="typed" aria-hidden="true" data-full="${text}" data-key="${key}">${typed ? text : ''}</span></p>
        ${single ? html`<span class="more" aria-hidden="true">&#9660;</span>` : ''}
      </section>
      <div class="choices pad ${typed ? '' : 'wait'}">
        ${node.choices.map((ch, i) => {
          const primary = !!(ch.act || ch.reward || ch.goto === 'waystone');
          return html`<button class="btn ${primary ? '' : 'cream'} block choice-btn" data-act="choose" data-arg="${i}" data-k="ch-${i}">${handinIcons(ctx, ch)}<span>${ch.label}</span></button>`;
        })}
      </div>
      <div style="height:calc(16px + var(--safe-bottom));flex:none"></div>
    </main>`;
  },
  actions: {
    ...discoveryActions,
    leave(ctx) {
      ctx.ui('place').node = null;
      ctx.back();
    },
    speech(ctx) {
      // tap the speech box: finish the line, or (for a plain "go on" line) carry on
      const u = ctx.ui('place');
      const out = document.querySelector('.speech .typed');
      if (out && !(u.typedKey === out.dataset.key && u.typedDone)) {
        u.finishLine?.();
        return;
      }
      const { node } = currentNode(ctx, placeNpc(ctx));
      if (node.choices.length === 1 && node.choices[0].next && !node.choices[0].act) place.actions.choose(ctx, '0');
    },
    npc(ctx, n) {
      const u = ctx.ui('place');
      if (u.npc === n) return;
      u.npc = n;
      u.node = null;
      ctx.sfx('ui_tap', 0.4);
      if (!ctx.state.story?.npcsMet?.[n]) ctx.act(Q.markNpcMet, n);
      ctx.rerender();
    },
    quest(ctx, qid) {
      openStoryQuest(ctx, qid);
    },
    choose(ctx, i) {
      const npc = placeNpc(ctx);
      const { node, nodes } = currentNode(ctx, npc);
      const ch = node.choices[Number(i)];
      if (!ch) return;
      const u = ctx.ui('place');
      if (ch.act?.kind === 'met') ctx.act(Q.markNpcMet, ch.act.npc); // a one-time scene was seen
      if (ch.leave) {
        u.node = null;
        ctx.sfx('ui_tap', 0.4);
        ctx.back();
        return;
      }
      if (ch.goto) {
        u.node = null;
        if (ch.goto === 'journey') {
          ctx.app.ui.journey = { ...(ctx.app.ui.journey || {}), tab: 'daily' };
          ctx.app.tab('journey');
        } else if (ch.goto === 'discover') {
          ctx.app.ui.journey = { ...(ctx.app.ui.journey || {}), tab: 'daily' };
          ctx.app.tab('journey');
        } else if (ch.goto.startsWith('prep:')) ctx.app.go('prep', { id: ch.goto.slice(5) });
        else if (ch.goto === 'kitchen' || ch.goto === 'apothecary') ctx.app.go('station', { id: ch.goto });
        else if (ch.goto === 'garden' || ch.goto === 'cottage') ctx.app.go(ch.goto);
        else ctx.app.go('place', { id: ch.goto }, { replace: true });
        return;
      }
      if (ch.npc) {
        place.actions.npc(ctx, ch.npc);
        return;
      }
      if (ch.reward) {
        u.node = null;
        openStoryReward(ctx, ch.reward, { then: Q.QUESTS[ch.reward].line ? 'stay' : 'village' });
        return;
      }
      if (ch.act) {
        const r = ch.act.kind === 'accept'
          ? ctx.act(Q.acceptStoryQuest, ch.act.quest)
          : ctx.act(Q.storyHandIn, ch.act.quest, ch.act.turnIn);
        if (r.error) return;
        // keep this conversation's nodes so the follow-up line still shows after the state moved on
        u.extraNodes = nodes;
        u.node = ch.then;
        if (ch.act.kind === 'accept') {
          ctx.sfx('reward_chime', 0.6);
          ctx.toast(`Story quest started: ${Q.QUESTS[ch.act.quest].title}`, 'ok', 'journey');
        } else {
          ctx.sfx(ch.act.turnIn === 'restore' ? 'evolve_fanfare' : 'purchase');
          u.flare = ch.act.turnIn === 'restore' ? 'restore' : 'give';
          setTimeout(() => {
            u.flare = null;
            ctx.rerender();
          }, 1400);
        }
        ctx.rerender();
        return;
      }
      if (ch.next) {
        u.node = ch.next;
        ctx.sfx('ui_tap', 0.3);
        ctx.rerender();
      }
    },
  },
};

// ------------------------------------------------------------------ Journey > Story
// A trail job whose encounter is waiting: the Journey's highlighted call to it (the board's Trail Discovery).
const DISTURB = {
  befriend: (C, place) => ({ title: `Something stirs in ${place}`, text: `A rare ${C.name} was seen near the arch. It seems cautious, but curious. Go and say hello.` }),
  hollow: (C, place) => ({ title: `${place}: disturbance detected`, text: `Strange Hollow energy has been detected in ${place}. Investigate the source.` }),
  boss: (C, place) => ({ title: `${place}: a presence awakens`, text: 'Something ancient sleeps in the gate past the bridge. Its light is fading.' }),
};

export function disturbanceCards(ctx) {
  return (ctx.d.story.encounters || []).filter((v) => TR.ENCOUNTERS[v.id]).map((v) => {
    const E = TR.ENCOUNTERS[v.id];
    const C = TR.CREATURES[E.creature];
    const place = TR.PLACE_NAMES[E.place].replace(/^the /, 'the ');
    const Place = place.replace(/^the /, 'The ');
    const d = (C.boss ? DISTURB.boss : E.goal === 'befriend' ? DISTURB.befriend : DISTURB.hollow)(C, E.goal === 'befriend' ? place : Place);
    const motes = Array.from({ length: 9 }, (_, i) => html`<i style="--i:${i};--x:${8 + ((i * 41) % 84)}%"></i>`);
    return html`<button class="card disturb ${C.kind}" data-act="disturb" data-arg="${v.id}" data-k="dist-${v.id}" aria-label="${d.title}. ${d.text}">
      <span class="ds-pic"><img class="bg" src="${url(manifest().trails.scenes[E.scene].file)}" alt=""><img class="cr" src="${icon('creature_' + C.id)}" alt=""><span class="motes" aria-hidden="true">${motes}</span></span>
      <span class="ds-tx"><span class="ds-kick">${E.goal === 'befriend' ? 'Encounter ready' : 'Hollow detected'}</span><b>${d.title.replace(/^the /, 'The ')}</b><small>${d.text}</small></span>
      <span class="chev" aria-hidden="true">&rsaquo;</span></button>`;
  });
}

// The Story tab is a journal: what's waiting for you right now on top (encounters, then active and new
// stories as full entries), what's coming next as short "locked" lines, the chapter card, and everything
// finished folded away under one toggle, so the page is about the next adventure, not the last five.
const LINES = { quests: 'Village Tales', home: 'Home Tales', trail: 'Lumen Trails', side: 'Side story' };
const rank = (v) => (v.next?.kind === 'handin' || v.next?.kind === 'encounter' ? 0 : v.accepted ? 1 : 2);

export function storyTab(ctx) {
  const st = ctx.d.story;
  const done = st.quests.filter((v) => v.completed).length;
  const dist = disturbanceCards(ctx);
  const distIds = new Set((st.encounters || []).map((v) => v.id));
  const all = Object.entries(LINES).flatMap(([k, line]) => (st[k] || []).map((v) => ({ v, line })));
  const active = all.filter(({ v }) => !v.completed && v.phase !== 'locked' && !distIds.has(v.id)).sort((a, b) => rank(a.v) - rank(b.v));
  const soon = all.filter(({ v }) => !v.completed && v.phase === 'locked').sort((a, b) => (a.v.level || 0) - (b.v.level || 0)).slice(0, 3);
  const finished = all.filter(({ v }) => v.completed);
  const open = !!ctx.ui('journey').doneOpen;
  return html`${dist.length ? html`<h2 class="h-sec sec-head" style="margin-top:2px">Main Quests</h2><div class="list">${dist}</div>` : ''}
    <h2 class="h-sec sec-head" style="margin-top:${dist.length ? 6 : 2}px">Your adventures</h2>
    ${active.length ? html`<div class="list">${active.map(({ v, line }) => storyRow(v, line))}</div>`
      : html`<div class="card inset all-caught-up"><img src="${icon('journey')}" alt="" width="40" height="40"><div><b class="h-card">All caught up</b><div class="small muted">New stories open as your Evochi grows and the village needs a hand.</div></div></div>`}
    ${soon.length ? html`<h2 class="h-sec sec-head" style="margin-top:6px">Coming up</h2>
      <div class="card inset mini-list" role="list">${soon.map(({ v, line }) => html`<button class="mini-row locked" role="listitem" data-act="story-quest" data-arg="${v.id}" data-k="sq-${v.id}">
        <img src="${icon('lock')}" alt="" class="ic"><span class="t">${v.title}<small>${line} · ${nextText(v)}</small></span><span class="tag small neutral">Lv ${v.level}</span></button>`)}</div>` : ''}
    <section class="card chapter-card" aria-label="${Q.CHAPTER.name}">
      <img src="${squareArt(st.flags)}" alt="" class="cover">
      <div class="in"><div class="tiny" style="color:#FFF6E6">${Q.CHAPTER.name}</div><b class="h-card" style="color:#FFF">${Q.CHAPTER.title}</b>
        <div class="row" style="gap:6px;margin-top:6px"><span class="tag small stage">${done} / ${st.quests.length} quests</span>${st.titles.length ? html`<span class="tag small ok">${Q.TITLES[st.titles[0]].name}</span>` : ''}</div></div>
      <button class="btn sm" data-act="visit-village" data-k="j-village" style="position:absolute;right:10px;bottom:10px">Visit Village</button>
    </section>
    ${finished.length ? html`<button class="done-toggle" data-act="j-done" aria-expanded="${open}" data-k="j-done"><img src="${icon('trophy')}" alt=""><span class="grow">Completed stories <b>(${finished.length})</b></span><span class="chev" aria-hidden="true">${open ? '▴' : '▾'}</span></button>
      ${open ? html`<div class="card inset mini-list" role="list">${finished.map(({ v, line }) => html`<button class="mini-row" role="listitem" data-act="story-quest" data-arg="${v.id}" data-k="sq-${v.id}">
        <img src="${npcSprite(Q.QUESTS[v.id].giver, 'happy')}" alt="" class="face"><span class="t">${v.title}<small>${line}</small></span><span class="ck" aria-label="Complete">${ICON.checkDark}</span></button>`)}</div>` : ''}` : ''}
    <p class="small muted" style="margin:2px 4px">Story walks only count steps taken after you accept a quest. Rest days never break them, and nothing expires. Side stories never block the main story.</p>`;
}

function storyRow(v, line) {
  return html`<button class="card story-quest ${v.completed ? 'claimed' : ''}" data-act="story-quest" data-arg="${v.id}" data-k="sq-${v.id}">
    <img src="${npcSprite(Q.QUESTS[v.id].giver, v.completed ? 'happy' : 'neutral')}" alt="" class="face">
    <div style="min-width:0;text-align:left">${line ? html`<div class="kick">${line}</div>` : ''}<div class="row" style="gap:6px;flex-wrap:wrap"><span class="t">${v.title}</span>${statusTag(v)}</div>
      <div class="small muted">${nextText(v)}</div>
      ${v.accepted && !v.completed ? html`<div style="margin-top:4px">${walkBar(v)}</div>` : ''}</div>
    <span class="chev" aria-hidden="true">&rsaquo;</span></button>`;
}

// ------------------------------------------------------------------ Bag > Quest Pouch
export function pouchGrid(ctx, sel, cols) {
  const pouch = ctx.d.story.pouch;
  const ids = Object.keys(Q.QUEST_MATERIALS).filter((id) => pouch[id] > 0);
  if (!ids.length) {
    return html`<div class="empty" style="grid-column:1/-1"><img src="${icon('journey')}" alt="" width="54" height="54" style="opacity:.6"><p class="body" style="margin:6px 0 10px"><b>Your Quest Pouch is empty.</b><br>Items you collect for Sunlit Village's story land here.</p><button class="btn sm" data-act="visit-village" data-k="bag-village">Visit Village</button></div>`;
  }
  return ids.map((id) => html`<button class="tile quest-tile" role="listitem" aria-pressed="${sel === id}" data-act="sel-q" data-arg="${id}" data-k="t-${id}" aria-label="${Q.QUEST_MATERIALS[id].name}, quest item${pouch[id] > 1 ? `, ${pouch[id]} owned` : ''}">
    <span class="qtag">Quest</span><img src="${itemImg(id)}" alt="">${pouch[id] > 1 ? html`<span class="qty">x${pouch[id]}</span>` : ''}<span class="nm">${Q.QUEST_MATERIALS[id].name}</span></button>`);
}

export function pouchDetail(ctx, id) {
  const m = Q.QUEST_MATERIALS[id];
  const trail = m.usedBy === 'ruins' || m.usedBy === 'gate';
  const who = m.usedBy === 'waystone' ? 'the Waystone' : trail ? TR.PLACE_NAMES[m.usedBy] : SPEAKER[m.usedBy].name;
  const placeId = m.usedBy === 'waystone' ? 'waystone' : trail ? 'prep:' + m.quest : Q.NPCS[m.usedBy].location;
  return html`<div class="card detail quest-detail" aria-live="polite">
    <div class="pic"><img src="${itemImg(id)}" alt=""></div>
    <div style="min-width:0"><b class="h-card">${m.name}</b>
      <div class="row" style="gap:4px;margin:4px 0;flex-wrap:wrap"><span class="tag small" style="background:#E7EEDF;color:#43523D;border-color:#7F9871">Quest item</span><span class="tag small cream">Can't trade</span><span class="tag small cream">Can't sell</span></div>
      <div class="small" style="color:var(--ink-700)">${m.desc}</div><div class="tiny muted" style="margin-top:3px">Used by ${who}</div></div>
    <div class="acts"><button class="btn sm" data-act="goto-place" data-arg="${placeId}" data-k="d-goto">Go to ${who.replace('the ', '')}</button></div></div>`;
}

export function storySourceTag(id) {
  const it = ITEMS[id];
  if (it?.acquisition !== 'story') return '';
  return html`<div class="tiny muted">${STORY_SOURCE[it.originQuest]}: ${Q.QUESTS[it.originQuest].title}</div>`;
}
