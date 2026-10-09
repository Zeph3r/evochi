// S09 Bag / inventory (style guide §11, §19).
import * as G from '../game/state.js';
import { ITEMS, SLOT_LABEL, DECOR_SLOTS, CATEGORY_LABEL } from '../game/catalog.js';
import { html, raw, fmt } from '../ui/dom.js';
import { icon, itemImg } from '../ui/assets.js';
import { ICON } from '../ui/icons.js';
import { coinPill, nav, titleImg, rarityTag } from '../core/app.js';
import { petScene, openHabitatSheet } from './home.js';

const CATS = [
  { id: 'wearable', label: 'Wearables', icon: 'wearables' },
  { id: 'consumable', label: 'Consumables', icon: 'consumables' },
  { id: 'decoration', label: 'Decorations', icon: 'decorations' },
];
const SLOT_UI = { head: 'Head', back: 'Back', neck: 'Accessory' };

function owned(state, cat) {
  return Object.entries(state.inventory)
    .filter(([id, v]) => v.quantity > 0 && ITEMS[id] && ITEMS[id].category === cat)
    .map(([id]) => id)
    .sort((a, b) => ITEMS[a].name.localeCompare(ITEMS[b].name));
}

export const bag = {
  id: 'bag',
  scene(ctx) {
    const u = ctx.ui('bag');
    const sc = petScene(ctx, { platform: true, decor: null, focus: { x: 0.5, y: u.groundY || 0.33 } });
    const eq = { ...(ctx.state.pet.equipped || {}) };
    const sel = u.sel && ITEMS[u.sel];
    if (sel && sel.category === 'wearable') eq[sel.slot] = u.sel; // temporary try-on preview
    sc.pet.equipped = Object.values(eq);
    sc.pet.sleeping = false;
    return sc;
  },
  afterLayout(ctx, el) {
    const sh = el.querySelector('.bag-sheet');
    const top = sh.getBoundingClientRect().top - ctx.app.root.getBoundingClientRect().top;
    ctx.ui('bag').groundY = Math.round(top - 22);
    return bag.scene(ctx);
  },
  position(ctx, el) {
    const pr = ctx.scene.petRect();
    if (!pr) return;
    const W = ctx.app.root.clientWidth;
    const cx = pr.left + pr.w / 2;
    const midY = pr.top + pr.h * 0.62;
    const bw = 64;
    const vis = pr.w * 0.32;
    const place = (sel, x) => {
      const b = el.querySelector(sel);
      if (b) Object.assign(b.style, { left: Math.max(6, Math.min(W - bw - 6, x)) + 'px', top: midY - 38 + 'px' });
    };
    const roomRight = W - 6 - (cx + vis + 14);
    if (roomRight >= bw * 2 + 10) {
      place('[data-slot=head]', cx - vis - bw - 14);
      place('[data-slot=back]', cx + vis + 14);
      place('[data-slot=neck]', cx + vis + 14 + bw + 10);
    } else {
      // narrow phones: Head and Back stack on the left, Accessory on the right
      const leftX = Math.max(6, cx - vis - bw - 10);
      const hb = el.querySelector('[data-slot=head]');
      const bb = el.querySelector('[data-slot=back]');
      const top = Math.max(70, midY - 82);
      if (hb) Object.assign(hb.style, { left: leftX + 'px', top: top + 'px' });
      if (bb) Object.assign(bb.style, { left: leftX + 'px', top: top + 84 + 'px' });
      place('[data-slot=neck]', Math.min(W - bw - 6, cx + vis + 10));
    }
    const tag = el.querySelector('.preview-tag');
    if (tag) Object.assign(tag.style, { left: cx + 'px', top: Math.max(64, pr.top + pr.h * 0.02 - 34) + 'px' });
  },
  onPetTap(ctx) {
    ctx.scene.react('pet');
    ctx.sfx('pet_chirp');
  },
  render(ctx) {
    const s = ctx.state;
    const p = s.pet;
    const u = ctx.ui('bag');
    const cat = u.cat || 'wearable';
    const list = owned(s, cat);
    if (u.sel && (!ITEMS[u.sel] || ITEMS[u.sel].category !== cat || !G.ownedQty(s, u.sel))) u.sel = null;
    if (!u.sel && list.length && cat !== 'wearable') u.sel = list[0];
    if (!u.sel && cat === 'wearable') u.sel = Object.values(p.equipped || {})[0] || list[0] || null;
    const sel = u.sel;
    const cols = ctx.W >= 370 ? 4 : 3;
    const newWear = owned(s, 'wearable').some((id) => !Object.values(p.equipped || {}).includes(id)) && !u.seenWear;
    return html`<main class="screen" aria-label="Bag">
      <header class="hud">${titleImg('title_bag', 'Bag')}${coinPill(ctx)}</header>
      <h1 class="sr-only">Bag</h1>
      <span class="preview-tag" aria-hidden="true">Preview</span>
      ${Object.entries(SLOT_UI).map(([slot, label]) => {
        const id = p.equipped?.[slot];
        const active = sel && ITEMS[sel]?.slot === slot;
        return html`<button class="slot-box ${active ? 'active' : ''}" data-slot="${slot}" data-act="slot" data-arg="${slot}" data-k="slot-${slot}" aria-label="${label} slot: ${id ? ITEMS[id].name : 'empty'}">
          ${id ? html`<img class="item" src="${itemImg(id)}" alt="">` : html`<img class="ph" src="${icon(slot === 'head' ? 'wearables' : slot === 'back' ? 'bag' : 'care')}" alt=""><span class="plus" aria-hidden="true">+</span>`}
          <span>${label}</span></button>`;
      })}
      <div class="spacer hero-space bag-hero" aria-hidden="true"></div>
      <section class="bag-sheet">
        <div class="tabs" role="tablist" aria-label="Categories" style="grid-template-columns:repeat(3,minmax(0,1fr))">
          ${CATS.map((c) => html`<button class="tab" role="tab" aria-selected="${c.id === cat}" data-act="cat" data-arg="${c.id}" data-k="cat-${c.id}"><img src="${icon(c.icon)}" alt=""><span>${c.label}</span>${c.id === 'wearable' && newWear ? raw('<i class="badge-dot" style="top:-4px;right:-4px"></i>') : ''}</button>`)}
        </div>
        <div class="sheet-bg bag-inner">
          <div class="grid fill-scroll" role="list" style="grid-template-columns:repeat(${cols},minmax(0,1fr))">
            ${list.length ? list.map((id) => {
              const it = ITEMS[id];
              const q = G.ownedQty(s, id);
              const eq = it.category === 'wearable' && p.equipped?.[it.slot] === id;
              const placed = it.category === 'decoration' && Object.values(s.nest.placements).includes(id);
              return html`<button class="tile" role="listitem" aria-pressed="${sel === id}" data-act="sel" data-arg="${id}" data-k="t-${id}" aria-label="${it.name}${q > 1 ? `, ${q} owned` : ''}${eq ? ', equipped' : ''}${placed ? ', placed' : ''}">
                <img src="${itemImg(id)}" alt="">${it.category !== 'wearable' && (q > 1 || it.category === 'consumable') ? html`<span class="qty">x${q}</span>` : ''}${eq || placed ? html`<span class="eq" aria-hidden="true">${ICON.check}</span>` : ''}<span class="nm">${it.name}</span></button>`;
            }) : html`<div class="empty" style="grid-column:1/-1"><img src="${icon(CATS.find((c) => c.id === cat).icon)}" alt="" width="54" height="54" style="opacity:.6"><p class="body" style="margin:6px 0 10px"><b>Nothing in this pocket yet.</b></p><button class="btn sm" data-act="shop" data-k="bag-shop">Visit the Market</button></div>`}
          </div>
          ${sel ? detail(ctx, sel) : ''}
        </div>
      </section>
      <div style="height:6px;flex:none"></div>
      ${nav(ctx, 'bag')}
    </main>`;
  },
  actions: {
    cat(ctx, c) {
      const u = ctx.ui('bag');
      u.cat = c;
      u.sel = null;
      if (c === 'wearable') u.seenWear = true;
      ctx.rerender();
    },
    sel(ctx, id) {
      const u = ctx.ui('bag');
      u.sel = id;
      if (ITEMS[id].category === 'wearable') {
        ctx.scene.react('equip');
        ctx.track('item_previewed', { item: id });
      }
      ctx.sfx('ui_tap', 0.4);
      ctx.rerender();
    },
    slot(ctx, slot) {
      const u = ctx.ui('bag');
      u.cat = 'wearable';
      u.sel = ctx.state.pet.equipped?.[slot] || Object.keys(ctx.state.inventory).find((id) => ITEMS[id]?.slot === slot && G.ownedQty(ctx.state, id)) || null;
      if (!u.sel) ctx.toast(`No ${SLOT_UI[slot].toLowerCase()} items yet - find some in the Market`, 'warn', 'shop');
      ctx.rerender();
    },
    equip(ctx, id) {
      const r = ctx.act(G.equip, id);
      if (!r.error) {
        ctx.scene.react('equip');
        ctx.sfx('reward_chime', 0.5);
        ctx.toast(`${ITEMS[id].name} equipped`, 'ok', 'wearables');
        ctx.track('accessory_equipped', { item: id });
      }
    },
    unequip(ctx, slot) {
      ctx.act(G.unequip, slot);
      ctx.sfx('ui_tap');
    },
    use(ctx, id) {
      const r = ctx.act(G.useConsumable, id);
      if (!r.error) {
        ctx.toast(`+${ITEMS[id].effect.vitality} vitality`, 'ok', 'heart');
        ctx.scene.react('pet');
        ctx.sfx('reward_chime', 0.6);
      }
    },
    place(ctx, id) {
      const s = ctx.state;
      const it = ITEMS[id];
      const free = Object.entries(DECOR_SLOTS).filter(([sid, sl]) => sl.accepts.includes(it.decor));
      const target = free.find(([sid]) => !s.nest.placements[sid]) || free[0];
      const r = ctx.act(G.placeDecoration, id, target[0]);
      if (!r.error) {
        ctx.toast(`${it.name} placed in the ${DECOR_SLOTS[target[0]].label.toLowerCase()} spot`, 'ok', 'decorations');
        ctx.sfx('ui_tap');
        ctx.track('decoration_placed', { item: id });
      }
    },
    arrange(ctx) {
      openHabitatSheet(ctx);
    },
    'unplace'(ctx, id) {
      const s = ctx.state;
      const sid = Object.entries(s.nest.placements).find(([k, v]) => v === id)?.[0];
      if (sid) ctx.act(G.removeDecoration, sid);
    },
    shop(ctx) {
      const u = ctx.ui('bag');
      ctx.app.ui.shop = { ...(ctx.app.ui.shop || {}), cat: u.cat === 'consumable' ? 'care' : u.cat === 'decoration' ? 'habitats' : 'wearables' };
      ctx.app.tab('shop');
    },
  },
};

function detail(ctx, id) {
  const s = ctx.state;
  const p = s.pet;
  const it = ITEMS[id];
  const d = ctx.d;
  let acts;
  let tag;
  if (it.category === 'wearable') {
    const eq = p.equipped?.[it.slot] === id;
    tag = SLOT_UI[it.slot];
    acts = html`<button class="btn sm" data-act="equip" data-arg="${id}" ${eq ? raw('disabled') : ''} data-k="d-equip">${ICON.shirt}<span>${eq ? 'Equipped' : 'Equip'}</span></button>
      <button class="btn sm cream" data-act="unequip" data-arg="${it.slot}" ${eq ? '' : raw('disabled')} data-k="d-remove">${ICON.trash}<span>Remove</span></button>`;
  } else if (it.category === 'consumable') {
    tag = 'Care';
    const cool = it.effect.recovery && d.pet.recoveryReadyAt > ctx.now;
    acts = html`<button class="btn sm green" data-act="use" data-arg="${id}" ${cool || d.pet.dead || d.pet.vitality >= 100 ? raw('disabled') : ''} data-k="d-use">Use</button>
      <span class="tiny muted center">${d.pet.vitality >= 100 ? 'Vitality full' : cool ? 'Cooling down' : `Vitality ${d.pet.vitality}`}</span>`;
  } else {
    tag = 'Decoration';
    const placed = Object.values(s.nest.placements).filter((v) => v === id).length;
    const q = G.ownedQty(s, id);
    acts = html`<button class="btn sm" data-act="place" data-arg="${id}" ${placed >= q ? raw('disabled') : ''} data-k="d-place">Place</button>
      <button class="btn sm cream" data-act="${placed ? 'unplace' : 'arrange'}" data-arg="${id}" data-k="d-unplace">${placed ? 'Remove' : 'Arrange'}</button>`;
  }
  return html`<div class="card detail" aria-live="polite">
    <div class="pic"><img src="${itemImg(id)}" alt=""></div>
    <div style="min-width:0"><b class="h-card">${it.name}</b>
      <div class="row" style="gap:4px;margin:4px 0;flex-wrap:wrap"><span class="tag small cream"><img src="${icon(it.category === 'wearable' ? 'wearables' : it.category === 'consumable' ? 'consumables' : 'decorations')}" alt="">${tag}</span>${rarityTag(id)}</div>
      <div class="small" style="color:var(--ink-700)">${it.desc}</div></div>
    <div class="acts">${acts}</div></div>`;
}
