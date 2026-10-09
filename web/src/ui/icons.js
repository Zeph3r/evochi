// Small line glyphs for UI chrome (chevrons, edit, check...). Illustrated objects use the voxel icon set.
import { raw } from './dom.js';

const S = (d, extra = '') =>
  raw(`<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" ${extra}>${d}</svg>`);

export const ICON = {
  back: S('<path d="M15 5l-7 7 7 7"/>'),
  next: S('<path d="M9 5l7 7-7 7"/>'),
  close: S('<path d="M6 6l12 12M18 6L6 18"/>'),
  edit: raw('<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 20l1.2-4.6L15.6 5a2 2 0 0 1 2.8 0l.6.6a2 2 0 0 1 0 2.8L8.6 18.8z" fill="#E9B04E" stroke="#6D4735" stroke-width="1.8" stroke-linejoin="round"/><path d="M4 20l1.2-4.6 3.4 3.4z" fill="#F7E2C4" stroke="#6D4735" stroke-width="1.6" stroke-linejoin="round"/><path d="M14 6.6l3.4 3.4" stroke="#6D4735" stroke-width="1.6"/></svg>'),
  check: S('<path d="M5 12.5l4.5 4.5L19 7.5"/>', 'stroke="#FFFFFF"'),
  checkDark: S('<path d="M5 12.5l4.5 4.5L19 7.5"/>'),
  plus: S('<path d="M12 5v14M5 12h14"/>'),
  up: raw('<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3l8 9h-5v9H9v-9H4z" fill="#5FA046"/></svg>'),
  trash: raw('<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 7h14l-1.2 13H6.2z" fill="#6D5A4E"/><path d="M3.5 6h17M9 6V4h6v2" stroke="#4D3E35" stroke-width="2" stroke-linecap="round"/><path d="M10 10v7M14 10v7" stroke="#F2E6D8" stroke-width="1.6"/></svg>'),
  shirt: raw('<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 3l4 2.5L16 3l5 4-3 3.5-1.5-1V21h-9V9.5L6 10.5 3 7z" fill="#6D4735" stroke="#4A2E22" stroke-width="1.2" stroke-linejoin="round"/></svg>'),
  hanger: S('<path d="M12 7a2 2 0 1 1 2-2c0 1-2 1.6-2 3v1M12 9l-9 7.5h18z"/>'),
  play: raw('<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 4.5l13 7.5-13 7.5z" fill="#4A2E22"/></svg>'),
  mail: raw('<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="2.5" y="5" width="19" height="14" rx="2" fill="#7A5A44"/><path d="M3 6l9 7 9-7" stroke="#F1E3CB" stroke-width="1.8" fill="none"/></svg>'),
  device: raw('<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="6" y="2.5" width="12" height="19" rx="3" fill="#3B2923"/><rect x="8" y="5" width="8" height="12" rx="1" fill="#BFE6F5"/><circle cx="12" cy="19.2" r="1" fill="#F1E3CB"/></svg>'),
  key: raw('<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="8" cy="12" r="4.5" fill="none" stroke="#3B2923" stroke-width="2.6"/><path d="M12.5 12H21M18 12v3M21 12v2.5" stroke="#3B2923" stroke-width="2.6" stroke-linecap="round"/></svg>'),
  grid: raw('<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="3" width="8" height="8" rx="2" fill="#4A3A32"/><rect x="13" y="3" width="8" height="8" rx="2" fill="#4A3A32"/><rect x="3" y="13" width="8" height="8" rx="2" fill="#4A3A32"/><rect x="13" y="13" width="8" height="8" rx="2" fill="#4A3A32"/></svg>'),
  info: raw('<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="10" fill="#399CC7"/><path d="M12 10.5v6.5" stroke="#fff" stroke-width="2.6" stroke-linecap="round"/><circle cx="12" cy="7" r="1.6" fill="#fff"/></svg>'),
  sync: S('<path d="M20 12a8 8 0 0 1-14 5.3M4 12a8 8 0 0 1 14-5.3M18 3v4h-4M6 21v-4h4"/>'),
  sound: S('<path d="M4 9h4l5-4v14l-5-4H4zM16 9a4 4 0 0 1 0 6M18.5 6.5a7.5 7.5 0 0 1 0 11"/>'),
};
