const fs = require('node:fs');
const path = require('node:path');
const esbuild = require('esbuild');
const { thirdPartyNotices } = require('./notices');

const result = esbuild.buildSync({
  absWorkingDir: __dirname,
  entryPoints: ['extension.js'],
  bundle: true,
  platform: 'node',
  external: ['vscode'],
  outdir: 'dist',
  minify: true,
  metafile: true,
});
fs.writeFileSync(path.join(__dirname, 'dist/THIRD-PARTY-NOTICES.txt'),
  thirdPartyNotices(__dirname, Object.keys(result.metafile.inputs)));
