// S13 Profile / Settings: account, goal, step source, notifications, accessibility, privacy, playtest tools.
import * as G from '../game/state.js';
import { CONFIG } from '../game/config.js';
import { deviceZone, HOUR, DAY } from '../game/time.js';
import { simulateWalk } from '../game/health.js';
import { html, raw, fmt, timeAgo } from '../ui/dom.js';
import { icon, url, manifest } from '../ui/assets.js';
import { ICON } from '../ui/icons.js';
import { titleImg } from '../core/app.js';

const ZONES = ['UTC', 'America/Los_Angeles', 'America/Denver', 'America/Chicago', 'America/New_York', 'America/Sao_Paulo',
  'Europe/London', 'Europe/Berlin', 'Africa/Lagos', 'Asia/Kolkata', 'Asia/Singapore', 'Asia/Tokyo', 'Australia/Sydney'];

function sw(on, act, label, k) {
  return html`<button class="switch" role="switch" aria-checked="${!!on}" aria-label="${label}" data-act="${act}" data-k="${k}"></button>`;
}

export const settings = {
  id: 'settings',
  scene: () => null,
  render(ctx) {
    const s = ctx.state;
    const pl = s.player;
    const st = pl.settings;
    const u = ctx.ui('settings');
    const conn = s.steps.connection;
    const zones = Array.from(new Set([pl.timezone, deviceZone(), ...ZONES]));
    const offDays = Math.round((s.debug?.clockOffset || 0) / DAY);
    return html`<main class="screen scroll paper" aria-label="Profile and settings">
      <div class="paper-top" style="height:120px"><img class="bg" src="${url(manifest().habitats.thumbs.forest)}" alt="">
        <header class="hud" style="position:absolute;left:0;right:0;top:0;justify-content:flex-start;gap:10px"><button class="back-btn" data-act="back" aria-label="Back" data-k="sback">${ICON.back}</button>${titleImg('title_profile', 'Profile')}</header></div>
      <h1 class="sr-only">Profile and settings</h1>
      <div class="pad stack" style="gap:10px;margin-top:-18px;position:relative;z-index:3;padding-bottom:calc(24px + var(--safe-bottom))">
        <section class="card" aria-label="Account">
          <div class="setting"><img src="${icon('paw')}" alt="" width="34" height="34"><div class="grow"><div class="t">${pl.accountType === 'guest' ? 'Guest player' : pl.email}${(s.story?.titleUnlocks || []).includes('first_lightkeeper') ? html` <span class="tag small stage" style="vertical-align:2px">First Lightkeeper</span>` : ''}</div>
            <div class="d">${pl.accountType === 'guest' ? 'Saved on this device only. Add an email so your Evochi can move to the mobile app.' : 'Local email profile (preview). Cloud linking happens in the mobile app.'}</div></div>
            ${pl.accountType === 'guest' ? html`<button class="btn sm" data-act="add-email" data-k="addem">Add email</button>` : ''}</div>
        </section>
        <section class="card" aria-label="Daily goal">
          <div class="setting"><img src="${icon('star')}" alt="" width="34" height="34"><div class="grow"><div class="t">Daily step goal</div><div class="d">A game target, not a health prescription. Changes apply from today.</div></div></div>
          <div class="stepper" style="padding:0 12px 12px"><button class="icon-btn" data-act="goal" data-arg="-500" aria-label="Decrease goal" data-k="gm">-</button><span class="val num" aria-live="polite">${fmt(pl.goal)}</span><button class="icon-btn" data-act="goal" data-arg="500" aria-label="Increase goal" data-k="gp">+</button></div>
        </section>
        <section class="card" aria-label="Step source" id="steps">
          <div class="setting"><img src="${icon('steps')}" alt="" width="34" height="34"><div class="grow"><div class="t">Step source</div>
            <div class="d">${conn === 'demo' ? 'Simulated step device (web preview)' : conn === 'manual' ? 'Manual entry (unverified)' : 'Not connected'}${s.steps.lastSync ? ` - last sync ${timeAgo(s.steps.lastSync, ctx.now)}` : ''}</div></div></div>
          <div class="row" style="padding:0 12px 12px;gap:6px;flex-wrap:wrap">
            <button class="btn sm ${conn === 'demo' ? 'green' : 'cream'}" data-act="conn" data-arg="demo" data-k="cd">Simulated device</button>
            <button class="btn sm ${conn === 'manual' ? 'green' : 'cream'}" data-act="conn" data-arg="manual" data-k="cm">Manual</button>
            <button class="btn sm cream" data-act="conn" data-arg="none" data-k="cn" ${conn === 'none' ? raw('disabled') : ''}>Disconnect</button>
          </div>
          <p class="small muted" style="margin:0 12px 12px">On iOS and Android, Evochi asks for read-only step count access via Apple Health or Health Connect. Missing data is shown as "sync pending", never as inactivity.</p>
        </section>
        <section class="card" aria-label="Notifications">
          <div class="setting"><img src="${icon('bell')}" alt="" width="34" height="34"><div class="grow"><div class="t">Daily reminder</div><div class="d">One gentle nudge if you haven't visited, outside quiet hours. Never about your health.</div></div>${sw(st.notifications, 'toggle', 'Daily reminder', 'tn')}</div>
          ${st.notifications ? html`<div class="row" style="padding:0 12px 12px;gap:8px"><span class="small">Quiet hours</span>
            <select class="select" data-input="qs" aria-label="Quiet hours start">${Array.from({ length: 24 }, (_, h) => html`<option value="${h}" ${h === st.quietStart ? raw('selected') : ''}>${String(h).padStart(2, '0')}:00</option>`)}</select>
            <span class="small">to</span>
            <select class="select" data-input="qe" aria-label="Quiet hours end">${Array.from({ length: 24 }, (_, h) => html`<option value="${h}" ${h === st.quietEnd ? raw('selected') : ''}>${String(h).padStart(2, '0')}:00</option>`)}</select></div>` : ''}
        </section>
        <section class="card" aria-label="Sound and accessibility">
          <div class="setting"><div class="grow"><div class="t">Sound effects</div></div>${sw(st.sound, 'toggle', 'Sound effects', 'ts')}</div>
          <div class="setting"><div class="grow"><div class="t">Ambient music</div></div>${sw(st.music, 'toggle', 'Ambient music', 'tm')}</div>
          <div class="setting"><div class="grow"><div class="t">Haptics</div></div>${sw(st.haptics, 'toggle', 'Haptics', 'th')}</div>
          <div class="setting"><div class="grow"><div class="t">Reduce motion</div><div class="d">Crossfades instead of bounces, flashes and particles.</div></div>${sw(st.reducedMotion, 'toggle', 'Reduce motion', 'tr')}</div>
          <div class="setting"><div class="grow"><div class="t">Classic villagers</div><div class="d">Flat, evenly lit villagers instead of ones lit by each room's lanterns and windows.</div></div>${sw(st.classicVillagers, 'toggle', 'Classic villagers', 'tv')}</div>
        </section>
        <section class="card" aria-label="Time zone">
          <div class="setting"><img src="${icon('pin')}" alt="" width="30" height="30"><div class="grow"><div class="t">Account time zone</div><div class="d">Decides when your day starts. Travelling doesn't change it unless you do.</div></div></div>
          <div style="padding:0 12px 12px"><select class="select" style="width:100%" data-input="tz" aria-label="Account time zone">${zones.map((z) => html`<option ${z === pl.timezone ? raw('selected') : ''}>${z}</option>`)}</select></div>
        </section>
        <section class="card" aria-label="Privacy and data">
          <div class="setting"><img src="${icon('lock')}" alt="" width="30" height="30"><div class="grow"><div class="t">Privacy & data</div><div class="d">Evochi stores daily step totals and game progress. Nothing leaves this device in the web preview.</div></div></div>
          <div class="setting"><div class="grow"><div class="t">Share anonymous usage events</div><div class="d">Product events only (no raw health data). Kept locally here.</div></div>${sw(st.analytics, 'toggle', 'Share usage events', 'ta')}</div>
          <div class="row" style="padding:0 12px 12px;gap:8px;flex-wrap:wrap"><button class="btn sm cream" data-act="export" data-k="exp">Export my data</button><button class="btn sm danger" data-act="delete" data-k="del">Delete all data</button></div>
        </section>
        <section class="card dev" aria-label="Playtest tools">
          <div class="setting"><img src="${icon('warning')}" alt="" width="30" height="30"><div class="grow"><div class="t">Playtest tools</div><div class="d">Preview-only shortcuts for testing progression. Clock offset: +${offDays} day${offDays === 1 ? '' : 's'}.</div></div></div>
          <div class="row" style="padding:0 12px 12px;gap:6px;flex-wrap:wrap">
            <button class="btn sm cream" data-act="dev" data-arg="coins" data-k="dv1">+500 coins</button>
            <button class="btn sm cream" data-act="dev" data-arg="day" data-k="dv6">Walk 1 goal day</button>
            <button class="btn sm cream" data-act="dev" data-arg="days" data-k="dv2">Walk 7 goal days</button>
            <button class="btn sm cream" data-act="dev" data-arg="evolve" data-k="dv3">Fast-track evolution</button>
            <button class="btn sm cream" data-act="dev" data-arg="skip" data-k="dv4">Skip 3 idle days</button>
            <button class="btn sm cream" data-act="dev" data-arg="herbs" data-k="dv5">+3 Healing Herbs</button>
          </div>
        </section>
        <p class="small muted center" style="margin:4px 0 0">${ctx.store.cloud?.status === 'on' ? 'Saved to your account and this device.' : 'Saved on this device.'} Evochi web preview - spec v1.0 - config ${CONFIG.version}${ctx.store.storageOk ? '' : ' - storage unavailable, progress kept in memory'}</p>
      </div>
    </main>`;
  },
  mount(ctx, el) {
    if (ctx.app.route.params?.focus === 'steps') {
      const t = el.querySelector('#steps');
      if (t) el.scrollTop = t.offsetTop - 80;
      ctx.app.route.params.focus = null;
    }
  },
  inputs: {
    tz(ctx, v) {
      ctx.act(G.setTimezone, v);
      ctx.toast(`Day boundaries now follow ${v}`, 'ok', 'pin');
    },
    qs(ctx, v) {
      ctx.act(G.updateSettings, { quietStart: Number(v) });
    },
    qe(ctx, v) {
      ctx.act(G.updateSettings, { quietEnd: Number(v) });
    },
  },
  actions: {
    toggle(ctx, arg, el) {
      const k = { tn: 'notifications', ts: 'sound', tm: 'music', th: 'haptics', tr: 'reducedMotion', ta: 'analytics', tv: 'classicVillagers' }[el.dataset.k];
      const st = ctx.state.player.settings;
      ctx.act(G.updateSettings, { [k]: !st[k] });
      ctx.app.applySettings();
      ctx.app.sceneSig = null;
      if (k === 'notifications' && !st[k]) ctx.toast('Reminder on. Your progress never depends on notifications.', 'ok', 'bell');
    },
    goal(ctx, d) {
      const g = Math.max(CONFIG.goal.min, Math.min(CONFIG.goal.max, ctx.state.player.goal + Number(d)));
      ctx.act(G.setGoal, g);
    },
    conn(ctx, c) {
      ctx.act(G.setConnection, c);
      ctx.toast(c === 'none' ? 'Step source disconnected. Your Evochi will wait for you.' : 'Step source updated', 'ok', 'steps');
    },
    'add-email'(ctx) {
      const u = ctx.ui('acct');
      ctx.modal({
        label: 'Add email',
        render: () => html`<div class="stack"><h2 class="h-sec">Add an email</h2>
          <input class="input" type="email" data-input="em" value="${u.v || ''}" data-autofocus placeholder="you@example.com" aria-label="Email">
          ${u.err ? html`<p class="field-err" role="alert">${u.err}</p>` : ''}
          <button class="btn block" data-act="em-save">Save</button><button class="btn cream block" data-act="modal-close">Cancel</button></div>`,
        inputs: { em: (c, v) => (u.v = v) },
        actions: {
          'em-save': (c) => {
            const v = (u.v || '').trim();
            if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v)) {
              u.err = 'Enter a valid email address.';
              c.app.renderModals();
              return;
            }
            const s = structuredClone(c.store.state);
            s.player.accountType = 'email';
            s.player.email = v;
            c.store.replace(s);
            c.closeModal();
            c.toast('Email added', 'ok', 'mail');
          },
        },
      });
    },
    async export(ctx) {
      const text = JSON.stringify(ctx.state, null, 2);
      const filename = `evochi-data-${new Date().toISOString().slice(0, 10)}.json`;
      let dl = null;
      try {
        dl = await window.claude?.use?.('downloads');
      } catch {}
      if (dl) {
        try {
          const r = await dl.save({ filename, data: text });
          if (r && r.status === 'saved') ctx.toast('Export saved', 'ok', 'lock');
          return;
        } catch (e) {
          if (e && e.code !== 'unavailable') return; // declined or cancelled: nothing to do
        }
      }
      // fallback: show the data so it can be copied
      ctx.modal({
        label: 'Your data',
        render: () => html`<div class="stack"><h2 class="h-sec">Your data</h2>
          <p class="small muted" style="margin:0">Everything Evochi stores about you, as JSON.</p>
          <textarea id="export-json" class="input" style="height:220px;font:12px/1.4 ui-monospace,monospace;padding:8px" readonly>${text}</textarea>
          <button class="btn block" data-act="copy">Copy to clipboard</button><button class="btn cream block" data-act="modal-close">Close</button></div>`,
        actions: {
          copy: (c) => {
            const ta = document.getElementById('export-json');
            navigator.clipboard?.writeText(text).then(
              () => c.toast('Copied', 'ok', 'lock'),
              () => (ta.focus(), ta.select(), c.toast('Select all and copy the text', 'warn', 'lock')),
            ) ?? (ta.focus(), ta.select());
          },
        },
      });
    },
    delete(ctx) {
      ctx.modal({
        center: true,
        label: 'Delete all data',
        render: () => html`<div class="stack"><h2 class="h-sec">Delete everything?</h2>
          <p class="body">This removes your Evochi, coins, items and step history from this device${ctx.store.cloud?.status === 'on' ? ' and from your account' : ''}. It can't be undone.</p>
          <button class="btn danger block" data-act="del-go">Delete all data</button><button class="btn cream block" data-act="modal-close" data-autofocus>Cancel</button></div>`,
        actions: {
          'del-go': async (c) => {
            c.closeModal();
            const cloud = c.store.cloud;
            if (cloud?.ref && cloud.status === 'on') {
              try {
                await cloud.ref.delete();
              } catch {}
            }
            c.app.ui = {};
            c.app.route = null;
            c.store.wipe();
          },
        },
      });
    },
    dev(ctx, what) {
      const store = ctx.store;
      if (what === 'coins') ctx.act((s, now) => G.grantCoins(s, 500, now));
      if (what === 'herbs') {
        const s = structuredClone(store.state);
        const cur = s.inventory.healing_herb || { quantity: 0, acquisitions: [] };
        cur.quantity += 3;
        cur.acquisitions.push({ at: store.now(), source: 'playtest', qty: 3 });
        s.inventory.healing_herb = cur;
        store.replace(s);
      }
      if (what === 'skip') {
        advance(store, 3, 0);
        ctx.toast('Skipped 3 days without steps', 'warn', 'warning');
      }
      if (what === 'day') {
        advance(store, 1, 1.05);
        ctx.toast('Walked to goal, then moved to the next day', 'ok', 'steps');
      }
      if (what === 'days') {
        advance(store, 7, 1.05);
        ctx.toast('Walked to goal on 7 days', 'ok', 'steps');
      }
      if (what === 'evolve') {
        const d = ctx.d;
        if (!d.pet || d.pet.evo.maxed) {
          ctx.toast('Already in final form', 'ok', 'evolve');
          return;
        }
        let guard = 0;
        while (!G.derive(store.state, store.now()).pet.evo.eligible && guard++ < 400) advance(store, 1, 1.5, true);
        store.emit();
        ctx.toast('Evolution is ready - visit Home!', 'ok', 'evolve');
      }
    },
  },
};

/** Walk `ratio` x goal on each of `days` days, advancing the preview clock one day at a time. */
function advance(store, days, ratio, quiet = false) {
  for (let i = 0; i < days; i++) {
    let s = store.state;
    if (ratio > 0) {
      const now = store.now();
      const goal = G.goalFor(s, G.derive(s, now).today);
      // like the Journey simulator, never reach back before an active story quest was accepted
      const st = s.story;
      const since = st?.activeQuestId ? st.questStates[st.activeQuestId]?.acceptedAt : 0;
      s = G.syncSteps(s, simulateWalk(Math.round(goal * ratio), now, { watch: false, minutes: 60, notBefore: since || 0 }), now).state;
    }
    s = structuredClone(s);
    s.debug.clockOffset = (s.debug.clockOffset || 0) + DAY;
    s = G.syncSteps(s, [], Date.now() + s.debug.clockOffset).state;
    store.state = s;
  }
  store.persist();
  if (!quiet) store.emit();
}
