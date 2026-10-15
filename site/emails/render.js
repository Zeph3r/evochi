// Tiny template renderer shared by the build script and the Pages Functions.
//   {{name}}            value, HTML-escaped
//   {{{name}}}          value, raw HTML
//   {{#flag}}…{{/flag}} shown when flag is truthy (arrays repeat the block once per item)
//   {{^flag}}…{{/flag}} shown when flag is falsy or empty
export function esc(v) {
  return String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

export function render(tpl, data) {
  const get = (k) => (k === '.' ? (Object.prototype.hasOwnProperty.call(data, '.') ? data['.'] : data) : k.split('.').reduce((o, p) => (o == null ? undefined : o[p]), data));
  let out = tpl.replace(/\{\{([#^])([\w.]+)\}\}([\s\S]*?)\{\{\/\2\}\}/g, (_, kind, key, inner) => {
    const v = get(key);
    const truthy = Array.isArray(v) ? v.length > 0 : !!v;
    if (kind === '^') return truthy ? '' : render(inner, data);
    if (!truthy) return '';
    if (Array.isArray(v)) return v.map((item) => render(inner, typeof item === 'object' && item !== null ? { ...data, ...item, '.': item } : { ...data, '.': item })).join('');
    return render(inner, data);
  });
  out = out.replace(/\{\{\{([\w.]+)\}\}\}/g, (_, k) => String(get(k) ?? ''));
  out = out.replace(/\{\{([\w.]+)\}\}/g, (_, k) => esc(get(k)));
  return out;
}

export const fmt = (n) => Number(n || 0).toLocaleString('en-US');
export const COLOUR_NAMES = { amber: 'Amber', forest: 'Forest', coral: 'Coral', ocean: 'Ocean', amethyst: 'Amethyst', obsidian: 'Obsidian' };
