const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');

const root = path.resolve(__dirname, '../..');
const page = fs.readFileSync(path.join(root, 'crates/ms-tooling/src/page.html'), 'utf8');
const site = fs.readFileSync(path.join(root, 'website/assets/_custom.scss'), 'utf8');
// Inspect CSS declarations only: no page startup or browser substitute.
const tokens = text => Object.fromEntries([...text.matchAll(/--([\w-]+):\s*(#[\da-f]{6})/g)].map(m => [m[1], m[2]]));
const blocks = [...page.matchAll(/:root(?:\[data-theme=dark\]|:not\(\[data-theme=light\]\))?\{([^}]+)\}/g)].map(m => m[1]);
const palettes = blocks.map(tokens);
const shared = {
  bg: 'body-background', fg: 'body-font-color', acc: 'color-link',
  mut: 'docs-muted', cm: 'docs-muted', line: 'gray-200', pan: 'gray-100',
  node: 'docs-code-bg', sel: 'docs-accent-bg', ent: 'docs-accent-bg',
  kw: 'docs-code-keyword', nu: 'docs-code-keyword', st: 'docs-code-string',
  fnc: 'docs-code-function', ty: 'docs-code-function',
};

test('code map follows public documentation tokens in light and both dark modes', () => {
  assert.equal(palettes.length, 3);
  for (const [i, theme] of ['light', 'dark', 'dark'].entries()) {
    const docs = tokens(site.match(new RegExp(`@mixin docs-${theme} \\{([^}]+)\\}`))[1]);
    for (const [mapToken, siteToken] of Object.entries(shared)) {
      assert.equal(palettes[i][mapToken], docs[siteToken], `${theme}: ${mapToken}`);
    }
    assert.ok(blocks[i].includes(`color-scheme:${theme}`));
  }
  assert.deepEqual(palettes[1], palettes[2], 'system and explicit dark themes agree');
  assert.match(page, /@media \(prefers-color-scheme:dark\)\{:root:not\(\[data-theme=light\]\)/);
});

function luminance(hex) {
  const rgb = hex.slice(1).match(/../g).map(v => parseInt(v, 16) / 255)
    .map(v => v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
  return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722;
}
function contrast(a, b) {
  const values = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (values[0] + 0.05) / (values[1] + 0.05);
}

test('map text, syntax, selections and semantic badges meet 4.5:1 contrast', () => {
  for (const palette of palettes) {
    for (const foreground of ['fg', 'mut', 'acc', 'kw', 'ty', 'st', 'nu', 'cm', 'fnc', 'var', 'own', 'brw', 'effs']) {
      for (const background of ['bg', 'pan', 'node']) {
        assert.ok(contrast(palette[foreground], palette[background]) >= 4.5, `${foreground} on ${background}: ${palette.bg}`);
      }
    }
    assert.ok(contrast(palette.acc, palette.sel) >= 4.5);
    for (const background of ['var', 'spawn', 'effs', 'mut']) {
      assert.ok(contrast(palette.badgefg, palette[background]) >= 4.5, `badge on ${background}`);
    }
    assert.equal(new Set(['acc', 'var', 'own', 'brw', 'effs', 'spawn'].map(k => palette[k])).size, 6);
  }
});

test('map theme has no external stylesheet, script, font or image dependency', () => {
  assert.doesNotMatch(page, /<link\b|<script\b[^>]+src\s*=|@import\b|@font-face\b|\burl\s*\(\s*['"]?(?!#)[^\s'"\)]/i);
  assert.doesNotMatch(page, /<(?:img|iframe)\b[^>]+src\s*=/i);
});
