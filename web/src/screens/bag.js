// S09 Bag / inventory (style guide §11, §19).
import * as G from '../game/state.js';
import { ITEMS, SLOT_LABEL, DECOR_SLOTS, CATEGORY_LABEL } from '../game/catalog.js';
import { html, raw, fmt } from '../ui/dom.js';
import { icon, itemImg } from '../ui/assets.js';
import { ICON } from '../ui/icons.js';
import { coinPill, nav, titleImg, rarityTag } from '../core/app.js';
import { petScene, openHabitatSheet } from './home.js';
import { pouchGrid, pouchDetail, storySourceTag } from './village.js';
import { QUEST_MATERIALS } from '../game/story.js';
import { CROPS, RECIPES, STATIONS, stationOpen } from '../game/home.js';
import { goHome } from './homeland.js';

const CATS = [
  { id: 'wearable', label: 'Wear', icon: 'wearables', aria: 'Wearables' },
  { id: 'consumable', label: 'Care', icon: 'consumables', aria: 'Consumables' },
  { id: 'decoration', label: 'Decor', icon: 'decorations', aria: 'Decorations' },
  { id: 'pantry', label: 'Pantry', icon: 'skill_farming', aria: 'Pantry: seeds and ingredients' },
  { id: 'pouch', label: 'Pouch', icon: 'journey', aria: 'Quest Pouch' },
];
const PANTRY = ['seed', 'ingredient'];
const STAR = '<svg class="stag" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.5l2.9 6 6.6.8-4.9 4.5 1.3 6.5L12 17l-5.9 3.3 1.3-6.5L2.5 9.3l6.6-.8z" fill="#F4B84E" stroke="#80531F" stroke-width="1.4" stroke-linejoin="round"/></svg>';
const SLOT_UI = { head: 'Head', back: 'Back', neck: 'Accessory' };

function owned(state, cat) {
  const cats = cat === 'pantry' ? PANTRY : [cat];
  return Object.entries(state.inventory)
    .filter(([id, v]) => v.quantity > 0 && ITEMS[id] && cats.includes(ITEMS[id].category))
    .map(([id]) => id)
    .sort((a, b) => cats.indexOf(ITEMS[a].category) - cats.indexOf(ITEMS[b].category) || ITEMS[a].name.localeCompare(ITEMS[b].name));
}
const inCat = (it, cat) => (cat === 'pantry' ? PANTRY.includes(it.category) : it.category === cat);

export const bag = {
  id: 'bag',
  scene(ctx) {
    const u = ctx.ui('bag');
    const wear = (u.cat || 'wearable') === 'wearable';
    // two presentations: the dressing room (Wear) gives the Evochi the stage; the other pockets give the grid the room
    const sc = petScene(ctx, { platform: true, decor: null, focus: { x: wear ? 0.5 : 0.45, y: u.groundY || 0.33 } });
    sc.pet.scale = wear ? 1.3 : 0.8;
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
    const bw = 60;
    const vis = pr.w * 0.24;
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
    const pouch = cat === 'pouch';
    const list = pouch ? [] : owned(s, cat);
    if (pouch) {
      const have = Object.keys(QUEST_MATERIALS).filter((id) => (ctx.d.story?.pouch[id] || 0) > 0);
      if (!have.includes(u.selQ)) u.selQ = have[0] || null;
    }
    if (u.sel && (!ITEMS[u.sel] || !inCat(ITEMS[u.sel], cat) || !G.ownedQty(s, u.sel))) u.sel = null;
    if (!u.sel && list.length && cat !== 'wearable') u.sel = list[0];
    if (!u.sel && cat === 'wearable') u.sel = Object.values(p.equipped || {})[0] || list[0] || null;
    const sel = u.sel;
    const cols = ctx.W >= 370 ? 4 : 3;
    const wear = cat === 'wearable';
    const newWear = owned(s, 'wearable').some((id) => !Object.values(p.equipped || {}).includes(id)) && !u.seenWear;
    return html`<main class="screen bag-screen ${wear ? 'mode-wear' : 'mode-inv'}" aria-label="Bag">
      <header class="hud">${titleImg('title_bag', 'Bag')}${coinPill(ctx)}</header>
      <h1 class="sr-only">Bag</h1>
      ${wear ? html`<span class="preview-tag" aria-hidden="true">${sel && ITEMS[sel]?.category === 'wearable' && p.equipped?.[ITEMS[sel].slot] !== sel ? 'Trying on' : 'Dressing room'}</span>` : ''}
      ${!wear ? '' : Object.entries(SLOT_UI).map(([slot, label]) => {
        const id = p.equipped?.[slot];
        const active = sel && ITEMS[sel]?.slot === slot;
        return html`<button class="slot-box ${active ? 'active' : ''}" data-slot="${slot}" data-act="slot" data-arg="${slot}" data-k="slot-${slot}" aria-label="${label} slot: ${id ? ITEMS[id].name : 'empty'}">
          ${id ? html`<img class="item" src="${itemImg(id)}" alt="">` : html`<img class="ph" src="${icon(slot === 'head' ? 'wearables' : slot === 'back' ? 'bag' : 'care')}" alt=""><span class="plus" aria-hidden="true">+</span>`}
          <span>${label}</span></button>`;
      })}
      <div class="spacer hero-space bag-hero" aria-hidden="true"></div>
      <section class="bag-sheet">
        <div class="tabs five" role="tablist" aria-label="Categories" style="grid-template-columns:repeat(5,minmax(0,1fr))">
          ${CATS.map((c) => html`<button class="tab" role="tab" aria-selected="${c.id === cat}" data-act="cat" data-arg="${c.id}" data-k="cat-${c.id}" aria-label="${c.aria || c.label}"><img src="${icon(c.icon)}" alt=""><span>${c.label}</span>${c.id === 'wearable' && newWear ? raw('<i class="badge-dot" style="top:-4px;right:-4px"></i>') : ''}</button>`)}
        </div>
        <div class="sheet-bg bag-inner">
          <div class="${wear ? 'wear-strip' : 'grid fill-scroll'}" role="list" style="${wear ? '' : `grid-template-columns:repeat(${cols},minmax(0,1fr))`}">
            ${pouch ? pouchGrid(ctx, u.selQ, cols) : list.length ? list.map((id) => {
              const it = ITEMS[id];
              const q = G.ownedQty(s, id);
              const eq = it.category === 'wearable' && p.equipped?.[it.slot] === id;
              const placed = it.category === 'decoration' && Object.values(s.nest.placements).includes(id);
              const story = it.acquisition === 'story';
              return html`<button class="tile ${story ? 'story-tile' : ''}" role="listitem" aria-pressed="${sel === id}" data-act="sel" data-arg="${id}" data-k="t-${id}" aria-label="${it.name}${q > 1 ? `, ${q} owned` : ''}${eq ? ', equipped' : ''}${placed ? ', placed' : ''}">
                ${story ? raw(STAR) : ''}<img src="${itemImg(id)}" alt="">${it.category !== 'wearable' && (q > 1 || it.category === 'consumable' || it.stackable) ? html`<span class="qty">x${q}</span>` : ''}${eq || placed ? html`<span class="eq" aria-hidden="true">${ICON.check}</span>` : ''}<span class="nm">${it.name}</span></button>`;
            }) : html`<div class="empty" style="grid-column:1/-1"><img src="${icon(CATS.find((c) => c.id === cat).icon)}" alt="" width="54" height="54" style="opacity:.6"><p class="body" style="margin:6px 0 10px"><b>Nothing in this pocket yet.</b></p><button class="btn sm" data-act="shop" data-k="bag-shop">Visit the Market</button></div>`}
          </div>
          ${pouch ? (u.selQ ? pouchDetail(ctx, u.selQ) : '') : sel ? (wear ? wearBar(ctx, sel) : detail(ctx, sel)) : ''}
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
      u.more = false;
      // the layout changes between the dressing room and the pockets: let the scene re-measure
      ctx.app.sceneSig = null;
      if (c === 'wearable') u.seenWear = true;
      ctx.rerender();
    },
    more(ctx) {
      const u = ctx.ui('bag');
      u.more = !u.more;
      ctx.rerender();
    },
    'sel-q'(ctx, id) {
      ctx.ui('bag').selQ = id;
      ctx.sfx('ui_tap', 0.4);
      ctx.rerender();
    },
    'goto-place'(ctx, id) {
      if (id.startsWith('prep:')) ctx.go('prep', { id: id.slice(5) });
      else ctx.go('place', { id });
    },
    sel(ctx, id) {
      const u = ctx.ui('bag');
      if (u.sel === id && ITEMS[id].category !== 'wearable') u.more = !u.more;
      else u.more = false;
      u.sel = id;
      const it = ITEMS[id];
      if (it.category === 'wearable') {
        ctx.scene.react('equip');
        ctx.track('item_previewed', { item: id });
      } else if (it.category === 'consumable' && !it.effect?.growth) ctx.scene.react('snack');
      else ctx.scene.react('inspect');
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
        const used = r.events.find((e) => e.type === 'used');
        const treat = r.events.find((e) => e.type === 'treat');
        ctx.toast(treat ? `${ctx.state.pet.name} loved the ${ITEMS[id].name}!${used.vitality ? ` +${used.vitality} vitality` : ''}` : `+${used.vitality} vitality`, 'ok', 'heart');
        ctx.scene.react(treat ? 'play' : 'pet');
        ctx.sfx(treat ? 'pet_chirp' : 'reward_chime', 0.6);
      }
    },
    home(ctx, where) {
      goHome(ctx, where);
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
      ctx.app.ui.shop = { ...(ctx.app.ui.shop || {}), cat: u.cat === 'consumable' ? 'care' : u.cat === 'decoration' ? 'habitats' : u.cat === 'pantry' ? 'garden' : 'wearables' };
      ctx.app.tab('shop');
    },
  },
};

// the dressing room's bar under the strip: what you're trying on and one big button (Equip, or Take off)
function wearBar(ctx, id) {
  const p = ctx.state.pet;
  const it = ITEMS[id];
  const eq = p.equipped?.[it.slot] === id;
  return html`<div class="wear-bar" aria-live="polite">
    <div class="wb-pic"><img src="${itemImg(id)}" alt=""></div>
    <div class="wb-info"><b>${it.name}</b><div class="row" style="gap:4px;flex-wrap:wrap"><span class="tag small cream"><img src="${icon('wearables')}" alt="">${SLOT_UI[it.slot]}</span>${rarityTag(id)}</div></div>
    ${eq ? html`<button class="btn cream wb-btn" data-act="unequip" data-arg="${it.slot}" data-k="d-remove" aria-label="Take off ${it.name}">${ICON.trash}<span>Take off</span></button>`
      : html`<button class="btn wb-btn" data-act="equip" data-arg="${id}" data-k="d-equip">${ICON.shirt}<span>Equip</span></button>`}
  </div>`;
}

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
  } else if (it.category === 'consumable' && it.effect.growth) {
    tag = 'Garden';
    acts = html`<button class="btn sm green" data-act="home" data-arg="garden" data-k="d-garden">Use in Garden</button>`;
  } else if (it.category === 'consumable') {
    tag = it.kind === 'meal' ? 'Homemade' : 'Care';
    const cool = it.effect.recovery && d.pet.recoveryReadyAt > ctx.now;
    const treatOpen = it.effect.treat && !(p.bondEvents || []).some((e) => e.key === d.today && e.type === 'treat');
    const full = d.pet.vitality >= 100 && !treatOpen;
    acts = html`<button class="btn sm green" data-act="use" data-arg="${id}" ${cool || d.pet.dead || full ? raw('disabled') : ''} data-k="d-use">${it.effect.treat ? 'Give' : 'Use'}</button>
      <span class="tiny muted center">${full ? 'Vitality full' : cool ? 'Cooling down' : treatOpen ? 'Treat: Bond +1' : `Vitality ${d.pet.vitality}`}</span>`;
  } else if (it.category === 'seed') {
    tag = 'Seed';
    const C = CROPS[it.crop];
    acts = html`<button class="btn sm green" data-act="home" data-arg="garden" data-k="d-plant">Plant</button>
      <span class="tiny muted center">Farming Lv ${C.level}</span>`;
  } else if (it.category === 'ingredient') {
    tag = 'Ingredient';
    const uses = Object.values(RECIPES).filter((R) => R.needs[id]);
    const room = uses.map((R) => R.station).find((st) => stationOpen(s, st));
    acts = room ? html`<button class="btn sm" data-act="home" data-arg="${room}" data-k="d-cook">${STATIONS[room].verb}</button>`
      : html`<button class="btn sm cream" data-act="home" data-arg="cottage" data-k="d-cottage">Cottage</button>`;
  } else {
    tag = 'Decoration';
    const placed = Object.values(s.nest.placements).filter((v) => v === id).length;
    const q = G.ownedQty(s, id);
    acts = html`<button class="btn sm" data-act="place" data-arg="${id}" ${placed >= q ? raw('disabled') : ''} data-k="d-place">Place</button>
      <button class="btn sm cream" data-act="${placed ? 'unplace' : 'arrange'}" data-arg="${id}" data-k="d-unplace">${placed ? 'Remove' : 'Arrange'}</button>`;
  }
  const more = !!ctx.ui('bag').more;
  return html`<div class="card detail item-card ${more ? 'open' : ''}" aria-live="polite">
    <div class="pic"><img src="${itemImg(id)}" alt=""></div>
    <div style="min-width:0"><b class="h-card">${it.name}</b>
      <div class="row" style="gap:4px;margin:4px 0;flex-wrap:wrap"><span class="tag small cream"><img src="${icon(CAT_ICON[it.category] || 'decorations')}" alt="">${tag}</span>${rarityTag(id)}</div>
      <div class="desc">${it.desc}</div>${more ? html`${storySourceTag(id) ? html`<div style="margin-top:4px">${storySourceTag(id)}</div>` : ''}${usedIn(id)}` : ''}
      <button class="more-btn" data-act="more" data-k="d-more" aria-expanded="${more}">${more ? 'Less' : 'More'} <span aria-hidden="true">${more ? '▴' : '▾'}</span></button></div>
    <div class="acts">${acts}</div></div>`;
}

const CAT_ICON = { wearable: 'wearables', consumable: 'consumables', decoration: 'decorations', seed: 'skill_farming', ingredient: 'skill_cooking' };

function usedIn(id) {
  if (ITEMS[id].category !== 'ingredient') return '';
  const uses = Object.values(RECIPES).filter((R) => R.needs[id]);
  if (!uses.length) return '';
  return html`<div class="tiny muted" style="margin-top:3px">Used in: ${uses.map((R) => ITEMS[R.makes].name).join(', ')}</div>`;
}
