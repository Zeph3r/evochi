// Build the web preview: bundle JS/CSS with esbuild, inline them (and the fonts) into one page,
// and copy the art next to it. Output: dist/index.html (+ dist/assets/**), dist/preview.html for local testing.
import { build } from 'esbuild';
import fs from 'node:fs';
import path from 'node:path';

const root = path.dirname(new URL(import.meta.url).pathname);
const dist = path.join(root, 'dist');
fs.rmSync(dist, { recursive: true, force: true });
fs.mkdirSync(dist, { recursive: true });

await build({
  entryPoints: [path.join(root, 'src/main.js')],
  bundle: true, minify: false, format: 'iife', target: ['es2020'], outfile: path.join(dist, 'app.js'),
  loader: { '.woff2': 'empty' }, external: ['assets/*'], logLevel: 'warning', legalComments: 'none',
});
let css = fs.readFileSync(path.join(dist, 'app.css'), 'utf8');
css = css.replace(/url\(["']?(assets\/fonts\/[^"')]+)["']?\)/g, (m, p) => {
  const b = fs.readFileSync(path.join(root, 'public', p)).toString('base64');
  return `url(data:font/woff2;base64,${b})`;
});
const js = fs.readFileSync(path.join(dist, 'app.js'), 'utf8').replace(/<\/script/gi, '<\\/script');
const tpl = fs.readFileSync(path.join(root, 'index.template.html'), 'utf8');
const page = tpl.replace('/*__CSS__*/', () => css).replace('/*__JS__*/', () => js);
fs.writeFileSync(path.join(dist, 'index.html'), page);
fs.rmSync(path.join(dist, 'app.js'));
fs.rmSync(path.join(dist, 'app.css'));
// art
fs.cpSync(path.join(root, 'public/assets'), path.join(dist, 'assets'), { recursive: true, filter: (s) => !s.endsWith('fonts') && !s.includes('/fonts/') });
// local preview mimicking the publish skeleton
const skel = `<!doctype html><html><head><meta charset=utf8><meta name=viewport content="width=device-width,initial-scale=1,viewport-fit=cover"><style>:root{color-scheme:light;padding-top:env(safe-area-inset-top);padding-bottom:env(safe-area-inset-bottom)}body{margin:0;font:14px system-ui}img{max-width:100%}[hidden]{display:none!important}</style></head><body>`;
fs.writeFileSync(path.join(dist, 'preview.html'), skel + page + '</body></html>');
const files = [];
(function walk(d) {
  for (const f of fs.readdirSync(d)) {
    const p = path.join(d, f);
    if (fs.statSync(p).isDirectory()) walk(p);
    else files.push(path.relative(dist, p));
  }
})(path.join(dist, 'assets'));
fs.writeFileSync(path.join(dist, 'files.json'), JSON.stringify(files));
console.log('page', (page.length / 1024).toFixed(0) + 'KB', 'assets', files.length);
