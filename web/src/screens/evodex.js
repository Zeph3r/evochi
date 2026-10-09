// S11 EvoDex: species, forms, colourways and the Hall of Memories.
import * as G from '../game/state.js';
import { CONFIG, PALETTES } from '../game/config.js';
import { html, raw, fmt } from '../ui/dom.js';
import { icon, url, manifest, spriteAttr, BLANK } from '../ui/assets.js';
import { coinPill, nav, titleImg, stageLabel } from '../core/app.js';

const DESC = {
  1: 'A small, scaly egg creature with the spirit of a lizard. Curious, cheerful and already full of adventurous energy.',
  2: 'More agile and alert, with a developing crest and tail. Shows greater personality while keeping the same voxel charm.',
  3: 'Strong, agile and full of life. Its crystalline crest and plated tail show years of growth and adventure.',
};

export const evodex = {
  id: 'evodex',
  scene: () => null,
  render(ctx) {
    const s = ctx.state;
    const p = s.pet;
    const u = ctx.ui('evodex');
    const pal = p?.paletteId || 'amber';
    const unlocked = (st) => !!s.unlocks[`stage:lizard:${st}`];
    const selStage = u.stage && unlocked(u.stage) ? u.stage : p?.stage || 1;
    const view = u.view || 'front';
    const found = PALETTES.filter((x) => s.unlocks[`palette:${x.id}`]).length;
    const ev = ctx.d.pet?.evo;
    return html`<main class="screen scroll paper" aria-label="EvoDex">
      <div class="paper-top"><img class="bg" src="${url(manifest().habitats.thumbs.cliffs)}" alt="">
        <header class="hud" style="position:absolute;left:0;right:0;top:0">${titleImg('title_evodex', 'EvoDex')}${coinPill(ctx)}</header></div>
      <h1 class="sr-only">EvoDex</h1>
      <div class="pad stack" style="gap:10px;margin-top:-28px;position:relative;z-index:3">
        <section class="card" style="padding:12px">
          <div class="row between"><h2 class="h-sec">Lizard family</h2><span class="tag stage">${[1, 2, 3].filter(unlocked).length} / 3 forms</span></div>
          <div class="stack" style="margin-top:8px">
            ${[1, 2, 3].map((st) => {
              const un = unlocked(st);
              const req = CONFIG.evolution[st];
              return html`<button class="card inset dex-stage ${un ? '' : 'locked'}" style="text-align:left;cursor:${un ? 'pointer' : 'default'};${selStage === st && un ? 'box-shadow:0 0 0 2px #F8D27C' : ''}" data-act="${un ? 'stage' : ''}" data-arg="${st}" data-k="dex-${st}" aria-label="${un ? stageLabel(st) : 'Undiscovered form'}">
                <div class="pic"><img data-sprite="${spriteAttr(st, pal, 'default', [], '', 160)}" src="${BLANK}" alt=""></div>
                <div class="grow"><div class="row" style="gap:6px"><b class="h-card">${un ? stageLabel(st) : '???'}</b><span class="tag small cream">#00${st}</span></div>
                  <p class="small" style="margin:4px 0 0;color:var(--ink-700)">${un ? DESC[st] : `Discovered at level ${req.level} with ${req.activeDays} active days.`}</p>
                  ${!un && ev && !ev.maxed && ev.next === st ? html`<div class="bar" style="height:8px;margin-top:6px"><i style="width:${Math.min(ev.levelProgress, ev.daysProgress) * 100}%"></i></div>` : ''}
                </div></button>`;
            })}
          </div>
        </section>
        <section class="card" style="padding:12px" aria-label="Turnaround">
          <div class="row between"><h2 class="h-card">${stageLabel(selStage)} turnaround</h2><span class="tiny muted">${PALETTES.find((x) => x.id === pal).label}</span></div>
          <div class="center" style="margin:8px 0;border-radius:12px;background:radial-gradient(circle at 50% 65%,#FFF9EC,#EFDFC9);padding:10px;min-height:150px;display:grid;place-items:center">
            <img data-sprite="${spriteAttr(selStage, pal, 'default', [], view, 220)}" src="${BLANK}" alt="${stageLabel(selStage)}, ${view} view" style="max-height:170px;max-width:100%">
          </div>
          <div class="turn" role="group" aria-label="View">${['front', 'left', 'back', 'right', 'top'].map((v) => html`<button aria-pressed="${v === view}" data-act="view" data-arg="${v}" data-k="dv-${v}"><img data-sprite="${spriteAttr(selStage, pal, 'default', [], v, 90)}" src="${BLANK}" alt="">${v}</button>`)}</div>
        </section>
        <section class="card" style="padding:12px" aria-label="Colourways">
          <div class="row between"><h2 class="h-card">Colourways</h2><span class="tag small cream">${found} / 6 found</span></div>
          <div class="swatches" style="margin-top:8px">${PALETTES.map((x) => {
            const f = !!s.unlocks[`palette:${x.id}`];
            return html`<div class="swatch" style="cursor:default" aria-label="${f ? x.label : 'Undiscovered colourway'}"><img data-sprite="${spriteAttr(1, x.id, 'default', [], '', 100)}" src="${BLANK}" alt="" style="${f ? '' : 'filter:brightness(0) opacity(.25)'}"></div>`;
          })}</div>
          <p class="small muted" style="margin:6px 0 0">Each new egg you raise in a different colour adds it to your EvoDex.</p>
        </section>
        <section class="card" style="padding:12px" aria-label="Hall of Memories">
          <h2 class="h-card">Hall of Memories</h2>
          ${s.pastPets.length ? html`<div class="stack" style="margin-top:8px">${s.pastPets.map((m) => html`<div class="row card inset" style="padding:8px">
              <img data-sprite="${spriteAttr(m.stage, m.paletteId, 'memorial', [], '', 90)}" src="${BLANK}" alt="" style="height:54px;width:64px;object-fit:contain">
              <div class="grow"><b class="h-card">${m.name}</b><div class="small muted">${stageLabel(m.stage)} - Lv ${m.peakLevel} - ${m.daysTogether} days together - ${fmt(m.lifetimeSteps)} steps</div></div></div>`)}</div>`
            : html`<p class="small muted" style="margin:6px 0 0">Evochi you raise and lay to rest are remembered here.</p>`}
        </section>
        <div style="height:4px"></div>
      </div>
      <div class="spacer"></div>
      <div style="position:sticky;bottom:0;padding-top:6px;z-index:5">${nav(ctx, 'evodex')}</div>
    </main>`;
  },
  actions: {
    stage(ctx, st) {
      ctx.ui('evodex').stage = Number(st);
      ctx.rerender();
    },
    view(ctx, v) {
      ctx.ui('evodex').view = v;
      ctx.rerender();
    },
  },
};
