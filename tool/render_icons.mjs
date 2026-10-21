// Renders assets/icon/*.svg to 1024 px PNGs for flutter_launcher_icons.
//
// resvg-js is not a project dependency; install it in a scratch folder:
//   npm install --prefix <tmp> @resvg/resvg-js@2.6.2
//   node tool/render_icons.mjs <tmp>/node_modules
//   .\tool\flutter.ps1 pub run flutter_launcher_icons
import { readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const modules = process.argv[2];
if (!modules) {
  console.error('usage: node tool/render_icons.mjs <path-to-node_modules>');
  process.exit(2);
}
const require = createRequire(join(modules, 'noop.js'));
const { Resvg } = require('@resvg/resvg-js');

const iconDir = join(dirname(fileURLToPath(import.meta.url)), '..', 'assets', 'icon');
const names = [
  'rune_reader_icon',
  'rune_reader_icon_background',
  'rune_reader_icon_foreground',
  'rune_reader_icon_monochrome',
];

for (const name of names) {
  const svg = readFileSync(join(iconDir, `${name}.svg`), 'utf8');
  const png = new Resvg(svg, {
    fitTo: { mode: 'width', value: 1024 },
    background: 'rgba(0,0,0,0)',
  }).render().asPng();
  writeFileSync(join(iconDir, `${name}.png`), png);
  console.log(`${name}.png ${png.length} bytes`);
}
