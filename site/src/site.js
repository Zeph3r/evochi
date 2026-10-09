// Evochi website: colourway switcher, pet hops, XP calculator, screenshot scroller, copy buttons.
(function () {
  'use strict';
  var doc = document;
  var $$ = function (sel, root) { return Array.prototype.slice.call((root || doc).querySelectorAll(sel)); };
  var reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Put the store the visitor can actually use first.
  var ua = navigator.userAgent || '';
  if (/android/i.test(ua)) doc.documentElement.classList.add('is-android');

  // ------------------------------------------------------------ colourways
  var LABELS = { amber: 'Amber', forest: 'Forest', coral: 'Coral', ocean: 'Ocean', amethyst: 'Amethyst', obsidian: 'Obsidian' };
  var STAGE_NAMES = { s01: 'Eggling', s02: 'Juvenile', s03: 'Elder' };
  function setPalette(pal, remember) {
    if (!LABELS[pal]) return;
    $$('img[data-stage]').forEach(function (img) {
      var st = img.getAttribute('data-stage');
      img.src = 'assets/img/pets/' + st + '-' + pal + '.webp';
      if (img.getAttribute('alt')) img.alt = 'The ' + STAGE_NAMES[st] + ' in the ' + LABELS[pal] + ' colourway';
    });
    $$('.swatch').forEach(function (b) { b.setAttribute('aria-pressed', String(b.getAttribute('data-palette') === pal)); });
    var out = doc.getElementById('pal-name');
    if (out) out.textContent = LABELS[pal];
    if (remember) { try { localStorage.setItem('evochi.palette', pal); } catch (e) { /* storage unavailable */ } }
  }
  $$('.swatch').forEach(function (b) {
    b.addEventListener('click', function () { setPalette(b.getAttribute('data-palette'), true); });
    // warm the cache so the swap is instant
    b.addEventListener('pointerenter', function () {
      var pal = b.getAttribute('data-palette');
      ['s01', 's02', 's03'].forEach(function (st) { var i = new Image(); i.src = 'assets/img/pets/' + st + '-' + pal + '.webp'; });
    }, { once: true });
  });
  try { var saved = localStorage.getItem('evochi.palette'); if (saved && saved !== 'amber') setPalette(saved, false); } catch (e) { /* ignore */ }

  // ------------------------------------------------------------ say hi
  var chirp = null;
  $$('.pet').forEach(function (btn) {
    btn.addEventListener('click', function () {
      if (!reduced) {
        btn.classList.remove('hop');
        void btn.offsetWidth;
        btn.classList.add('hop');
      }
      try {
        if (!chirp) { chirp = new Audio('assets/chirp.mp3'); chirp.volume = 0.5; }
        chirp.currentTime = 0;
        var p = chirp.play();
        if (p && p.catch) p.catch(function () {});
      } catch (e) { /* audio unavailable */ }
    });
    btn.addEventListener('animationend', function () { btn.classList.remove('hop'); });
  });

  // ------------------------------------------------------------ XP calculator (same rules as the game, config v1)
  var XP = { base: 100, milestones: [{ id: 'm25', r: 0.25, xp: 10 }, { id: 'm50', r: 0.5, xp: 15 }, { id: 'm100', r: 1, xp: 25 }], stretchMax: 20, stretchSpan: 0.5 };
  var TO_LEVEL_10 = 3340; // sum of roundToNearest10(120 + 40n + 4n^2) for n = 0..8
  var fmt = function (n) { return n.toLocaleString('en-US'); };
  function activityXp(S, G) {
    var base = Math.floor(XP.base * Math.min(S, G) / G);
    var ms = 0, reached = {};
    XP.milestones.forEach(function (m) { if (S >= m.r * G) { ms += m.xp; reached[m.id] = true; } });
    var span = XP.stretchSpan * G;
    var stretch = Math.floor(XP.stretchMax * Math.min(Math.max(S - G, 0), span) / span);
    return { base: base, milestones: ms, stretch: stretch, total: base + ms + stretch, reached: reached };
  }
  var range = doc.getElementById('steps-today');
  if (range) {
    var out = doc.getElementById('steps-out');
    var total = doc.getElementById('xp-total');
    var bar = doc.getElementById('xp-bar');
    var note = doc.getElementById('xp-note');
    var update = function () {
      var S = Number(range.value);
      var checked = doc.querySelector('input[name="goal"]:checked');
      var G = Number(checked ? checked.value : 7000);
      var r = activityXp(S, G);
      out.textContent = fmt(S);
      total.textContent = fmt(r.total);
      bar.style.width = Math.min(100, Math.round(100 * S / G)) + '%';
      $$('[data-chip]').forEach(function (c) {
        var id = c.getAttribute('data-chip');
        if (id === 'stretch') { c.textContent = 'Extra · +' + r.stretch; c.classList.toggle('on', r.stretch > 0); }
        else c.classList.toggle('on', !!r.reached[id]);
      });
      var msg;
      if (S === 0) msg = 'No steps yet. Rest days are part of the game: two low days a week never cost vitality.';
      else {
        msg = fmt(r.base) + ' XP for the walk' + (r.milestones ? ' plus ' + r.milestones + ' milestone XP' : '') + (r.stretch ? ' and ' + r.stretch + ' extra for going past your goal' : '') + '. ';
        msg += S >= 0.5 * G ? "That's an active day. " : "Under half your goal, so it isn't an active day yet. ";
        msg += 'At this pace an Eggling reaches level 10 in about ' + Math.ceil(TO_LEVEL_10 / r.total) + ' days.';
      }
      note.textContent = msg;
      range.setAttribute('aria-valuetext', fmt(S) + ' steps, ' + fmt(r.total) + ' XP');
    };
    range.addEventListener('input', update);
    $$('input[name="goal"]').forEach(function (g) { g.addEventListener('change', update); });
    update();
  }

  // ------------------------------------------------------------ screenshot scroller
  var shots = doc.getElementById('shots');
  $$('[data-scroll]').forEach(function (b) {
    b.addEventListener('click', function () {
      if (!shots) return;
      var card = shots.querySelector('.shot');
      var step = card ? card.getBoundingClientRect().width + 20 : 280;
      shots.scrollBy({ left: Number(b.getAttribute('data-scroll')) * step, behavior: reduced ? 'auto' : 'smooth' });
    });
  });

  // ------------------------------------------------------------ copy buttons (email addresses, request template)
  $$('[data-copy]').forEach(function (b) {
    b.addEventListener('click', function () {
      var target = doc.getElementById(b.getAttribute('data-copy'));
      if (!target) return;
      var text = target.textContent.trim();
      var status = b.parentNode.querySelector('.copied');
      var done = function (ok) {
        if (!status) return;
        status.textContent = ok ? 'Copied' : 'Select the text and copy it';
        setTimeout(function () { status.textContent = ''; }, 2500);
      };
      var select = function () {
        var sel = window.getSelection(); var range2 = doc.createRange();
        range2.selectNodeContents(target); sel.removeAllRanges(); sel.addRange(range2);
      };
      try {
        navigator.clipboard.writeText(text).then(function () { done(true); }, function () { select(); done(false); });
      } catch (e) { select(); done(false); }
    });
  });
})();
