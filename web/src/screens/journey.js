// S08 Journey: steps, sync status, quests and the week (style guide §14, §15, §18).
import * as G from '../game/state.js';
import { CONFIG } from '../game/config.js';
import { ITEMS } from '../game/catalog.js';
import { weekDays, addDays } from '../game/time.js';
import { activityXp, isActiveDay } from '../game/progression.js';
import { simulateWalk, manualEntry } from '../game/health.js';
import { html, raw, fmt, timeAgo } from '../ui/dom.js';
import { icon, url, manifest } from '../ui/assets.js';
import { ICON } from '../ui/icons.js';
import { coinPill, nav, titleImg } from '../core/app.js';
import { storyTab, openStoryQuest } from './village.js';

export const journey = {
  id: 'journey',
  scene: () => null,
  render(ctx) {
    const s = ctx.state;
    const d = ctx.d;
    const u = ctx.ui('journey');
    const conn = s.steps.connection;
    const pct = Math.min(1, d.todaySteps / d.goal);
    const xp = d.todayXp;
    const C = 2 * Math.PI * 54;
    const daily = d.quests.filter((q) => q.period === 'day');
    const weekly = d.quests.filter((q) => q.period === 'week');
    const days = weekDays(d.today);
    const tab = u.tab || 'daily';
    const srcLabel = conn === 'demo' ? 'Simulated step device' : conn === 'manual' ? 'Manual entry' : 'Not connected';
    const sources = html`        ${conn === 'demo' ? html`<section class="card dev" style="padding:12px" aria-label="Step simulator">
          <div class="row"><b class="h-card grow">Go for a walk</b><span class="tag small cream">Web preview</span></div>
          <p class="small muted" style="margin:4px 0 8px">Simulates time-stamped samples from a phone and a watch. Overlapping samples are de-duplicated, so they count once.</p>
          <div class="row" style="gap:6px;flex-wrap:wrap">
            ${[500, 1000, 2500].map((n) => html`<button class="btn sm green" data-act="walk" data-arg="${n}" data-k="w${n}">+${fmt(n)}</button>`)}
            <button class="btn sm" data-act="walk-goal" data-k="wgoal" ${d.todaySteps >= d.goal ? raw('disabled') : ''}>Reach goal</button>
          </div></section>` : ''}
        ${conn === 'manual' ? html`<section class="card" style="padding:12px" aria-label="Manual steps">
          <div class="row"><b class="h-card grow">Add steps manually</b><span class="tag small warn">Unverified</span></div>
          <div class="row" style="margin-top:8px"><input class="input" type="number" inputmode="numeric" min="0" max="60000" placeholder="e.g. 1500" data-input="manual" value="${u.manual || ''}" aria-label="Steps to add"><button class="btn sm" data-act="add-manual" data-k="addman">Add</button></div>
          <p class="small muted" style="margin:6px 0 0">Manual steps give XP and keep your Evochi healthy, but never unlock reward chests or cosmetic chances.</p></section>` : ''}`;
    return html`<main class="screen scroll paper" aria-label="Journey">
      <div class="paper-top"><img class="bg" src="${url(manifest().habitats.thumbs.meadow)}" alt="">
        <header class="hud" style="position:absolute;left:0;right:0;top:0">${titleImg('title_journey', 'Journey')}${coinPill(ctx)}</header></div>
      <h1 class="sr-only">Journey</h1>
      <div class="pad stack" style="gap:10px;margin-top:-28px;position:relative;z-index:3">
        <div class="tabs jtabs" role="tablist" aria-label="Quests" style="grid-template-columns:repeat(3,minmax(0,1fr));margin-top:0">
          ${[['daily', 'Daily', 'steps', daily.some((q) => q.eligible && !q.claimed)], ['weekly', 'Weekly', 'trophy', weekly.some((q) => q.eligible && !q.claimed)],
            ['story', 'Story', 'habitats', !!d.story?.turnIns.length]].map(([id, label, ic, dot]) => html`<button class="tab" role="tab" aria-selected="${tab === id}" data-act="jtab" data-arg="${id}" data-k="jt-${id}"><img src="${icon(ic)}" alt=""><span>${label}</span>${dot ? raw('<i class="badge-dot" style="top:-4px;right:-4px"></i>') : ''}</button>`)}
        </div>
        ${tab !== 'story' ? html`        <section class="card" style="padding:14px" aria-label="Today">
          <div class="row" style="gap:14px">
            <div class="ring" role="img" aria-label="${fmt(d.todaySteps)} of ${fmt(d.goal)} steps">
              <svg viewBox="0 0 120 120"><circle cx="60" cy="60" r="54" fill="none" stroke="#E7D9C8" stroke-width="12"/>
              <circle cx="60" cy="60" r="54" fill="none" stroke="url(#gr)" stroke-width="12" stroke-linecap="round" stroke-dasharray="${C}" stroke-dashoffset="${C * (1 - pct)}" style="transition:stroke-dashoffset .8s"/>
              <defs><linearGradient id="gr" x1="0" x2="1"><stop offset="0" stop-color="#A8D87E"/><stop offset="1" stop-color="#5FA046"/></linearGradient></defs></svg>
              <div class="in"><img src="${icon('steps')}" alt="" width="30" height="30"><b class="num" style="font-size:22px">${fmt(d.todaySteps)}</b><span class="tiny muted">of ${fmt(d.goal)}</span></div>
            </div>
            <div class="stack grow" style="gap:6px">
              <b class="h-card">Today</b>
              <div class="small"><b>${xp.total}</b> activity XP <span class="muted">(${xp.base} base + ${xp.milestones} milestones${xp.stretch ? ` + ${xp.stretch} stretch` : ''})</span></div>
              <div class="row" style="gap:4px;flex-wrap:wrap">${CONFIG.xp.milestones.map((m) => html`<span class="tag small ${xp.reached.includes(m.id) ? 'ok' : 'cream'}">${Math.round(m.ratio * 100)}% +${m.xp}</span>`)}</div>
              ${d.todayUnverified ? html`<span class="tag small warn">Includes unverified manual steps</span>` : ''}
            </div>
          </div>
          <div class="row" style="margin-top:12px;gap:10px;padding-top:10px;border-top:1.5px solid #EEDDC9">
            <img src="${icon(conn === 'none' ? 'warning' : 'steps')}" alt="" width="28" height="28">
            <div class="grow"><b class="small" style="font-family:var(--font-game)">${srcLabel}</b><div class="tiny muted" style="font-weight:600">${conn === 'none' ? 'Connect a source to earn from your steps' : `Last sync ${timeAgo(s.steps.lastSync, ctx.now)}`}</div></div>
            ${conn === 'none' ? html`<button class="btn sm green" data-act="connect" data-k="jconn">Connect</button>` : html`<button class="btn sm cream" data-act="sync" data-k="jsync" ${u.syncing ? raw('disabled') : ''}>${u.syncing ? html`<span class="spinner" style="width:16px;height:16px"></span>` : ICON.sync}<span>${u.syncing ? 'Syncing' : 'Sync'}</span></button>`}
          </div>
        </section>` : ''}
        ${tab !== 'story' ? sources : ''}
        ${tab === 'daily' ? html`<h2 class="h-sec sec-head" style="margin-top:4px">Daily quests</h2>
        <div class="list">${daily.map((q) => questRow(q))}</div>` : ''}
        ${tab === 'story' ? html`${storyTab(ctx)}${sources}` : ''}
        ${tab === 'weekly' ? html`<h2 class="h-sec sec-head" style="margin-top:4px">This week</h2>
        <div class="list">${weekly.map((q) => questRow(q))}</div>
        <section class="card" style="padding:12px" aria-label="Week overview">
          <div class="week">${days.map((k) => {
            const day = d.days[k];
            const steps = day ? day.steps : 0;
            const goal = G.goalFor(s, k);
            const log = d.pet?.vitalityLog.find((x) => x.key === k);
            let cls = '';
            let mark = '';
            if (k > d.today) cls = 'future';
            else if (steps >= goal) (cls = 'goal'), (mark = '✓');
            else if (isActiveDay(steps, goal)) (cls = 'active'), (mark = '½');
            else if (log?.kind === 'rest') (cls = 'rest'), (mark = 'z');
            else if (log?.kind === 'low') (cls = 'low'), (mark = '!');
            const dt = new Date(k + 'T12:00:00Z');
            return html`<div class="day ${cls} ${k === d.today ? 'today' : ''}" aria-label="${k}: ${fmt(steps)} steps">
              <span>${dt.toLocaleDateString('en-US', { weekday: 'short', timeZone: 'UTC' }).slice(0, 2)}</span><span class="dot">${mark}</span><span class="tiny" style="font-size:9.5px">${steps ? (steps >= 1000 ? (steps / 1000).toFixed(1) + 'k' : steps) : '-'}</span></div>`;
          })}</div>
          <div class="row" style="gap:6px;flex-wrap:wrap;margin-top:8px">
            <span class="tag small ok">✓ Goal</span><span class="tag small stage">½ Active</span><span class="tag small" style="background:#D6EDFB;color:#2D6A8C">z Rest day</span><span class="tag small danger">! Low</span>
          </div>
        </section>` : ''}
        <div style="height:4px"></div>
      </div>
      <div class="spacer"></div>
      <div style="position:sticky;bottom:0;padding-top:6px;z-index:5">${nav(ctx, 'journey')}</div>
    </main>`;
  },
  inputs: {
    manual(ctx, v) {
      ctx.ui('journey').manual = v;
    },
  },
  actions: {
    jtab(ctx, id) {
      ctx.ui('journey').tab = id;
      ctx.sfx('ui_tap', 0.3);
      ctx.rerender();
    },
    'story-quest'(ctx, id) {
      openStoryQuest(ctx, id);
    },
    claim(ctx, id) {
      const r = ctx.act(G.claimQuest, id);
      if (!r.error) {
        ctx.track('quest_claimed', { quest: id });
        const ev = r.events.find((e) => e.type === 'claimed');
        if (ev && ev.rewards.some((x) => x.chest)) chestModal(ctx, ev.rewards);
      }
    },
    connect(ctx) {
      ctx.go('settings', { focus: 'steps' });
    },
    sync(ctx) {
      const u = ctx.ui('journey');
      u.syncing = true;
      ctx.rerender();
      setTimeout(() => {
        u.syncing = false;
        ctx.act(G.syncSteps, []);
        ctx.track('step_sync_result', { ok: true });
      }, 700);
    },
    walk(ctx, n) {
      doWalk(ctx, Number(n));
    },
    'walk-goal'(ctx) {
      doWalk(ctx, Math.max(100, ctx.d.goal - ctx.d.todaySteps));
    },
    'add-manual'(ctx) {
      const u = ctx.ui('journey');
      const n = Math.round(Number(u.manual));
      if (!Number.isFinite(n) || n <= 0 || n > 60000) {
        ctx.toast('Enter a number of steps between 1 and 60,000', 'warn', 'steps');
        return;
      }
      u.manual = '';
      ctx.act((s, now) => G.syncSteps(s, manualEntry(n, now), now, { source: 'manual' }));
    },
  },
};

function doWalk(ctx, n) {
  const now = ctx.store.now();
  // the simulated walk "just happened"; it never reaches back before a story quest was accepted,
  // so a demo walk right after accepting counts in full (real step data keeps its own timestamps)
  const st = ctx.state.story;
  const since = st?.activeQuestId ? st.questStates[st.activeQuestId]?.acceptedAt : null;
  const samples = simulateWalk(n, now, { notBefore: since || 0 });
  ctx.act((s, t) => G.syncSteps(s, samples, t, { source: 'demo' }));
  ctx.sfx('ui_tap', 0.5);
  ctx.track('step_sync_result', { ok: true, bucket: n >= 2500 ? 'large' : 'small' });
}

function questRow(q) {
  const pct = Math.min(1, q.progress / q.target);
  return html`<div class="card quest ${q.claimed ? 'claimed' : ''}">
    <img src="${icon(q.icon)}" alt="">
    <div style="min-width:0"><div class="row" style="gap:6px"><span class="t">${q.title}</span>${q.chest ? html`<span class="tag small stage">+ chest</span>` : ''}</div>
      <div class="small muted">${q.desc}</div>
      <div class="bar green" aria-hidden="true"><i style="width:${pct * 100}%"></i></div>
      <div class="tiny muted" style="margin-top:3px">${q.label}</div></div>
    ${q.claimed ? html`<span class="tag ok">${ICON.checkDark}Claimed</span>`
      : html`<button class="btn sm ${q.eligible ? '' : 'cream'}" data-act="claim" data-arg="${q.id}" ${q.eligible ? '' : raw('disabled')} data-k="claim-${q.id}" aria-label="Claim ${q.coins} EvoCoins for ${q.title}"><img src="${icon('coin')}" alt="" width="20" height="20">${q.coins}</button>`}
  </div>`;
}

function chestModal(ctx, rewards) {
  ctx.sfx('reward_chime');
  ctx.modal({
    center: true,
    label: 'Reward chest',
    render: () => html`<div class="stack center">
      <img src="${icon('chest')}" alt="" width="96" height="96" style="margin:0 auto">
      <h2 class="h-sec">Reward chest opened!</h2>
      <div class="row" style="justify-content:center;gap:10px;flex-wrap:wrap">
        ${rewards.map((r) => r.kind === 'coins'
          ? html`<span class="tag stage" style="height:34px;font-size:16px"><img src="${icon('coin')}" alt="" style="width:24px;height:24px">+${r.amount}</span>`
          : html`<span class="tag ok" style="height:34px;font-size:15px"><img src="${url(manifest().items[r.itemId])}" alt="" style="width:26px;height:26px">${ITEMS[r.itemId].name}</span>`)}
      </div>
      <button class="btn block" data-act="modal-close" data-autofocus>Collect</button></div>`,
  });
}
