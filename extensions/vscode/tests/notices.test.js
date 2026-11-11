const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { thirdPartyNotices } = require('../notices');

function fixture(t, packages) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'manuscript-notices-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  for (const [relative, files] of Object.entries(packages)) {
    const directory = path.join(root, relative);
    fs.mkdirSync(directory, { recursive: true });
    fs.writeFileSync(path.join(directory, 'package.json'), JSON.stringify({
      name: relative.split('node_modules/').at(-1), version: '1.2.3', license: 'MIT',
    }));
    for (const [name, text] of Object.entries(files)) fs.writeFileSync(path.join(directory, name), text);
  }
  return root;
}

test('notices cover only bundled packages, deduplicated and sorted', t => {
  const root = fixture(t, {
    'node_modules/zeta': { 'License.txt': 'Copyright Z\n  Keep this spacing.\r\n' },
    'node_modules/alpha': { 'LICENSE': 'Copyright A\n' },
    'node_modules/dev-only': { 'LICENSE': 'Not bundled\n' },
  });
  const inputs = ['extension.js', 'node_modules/zeta/a.js', 'node_modules/alpha/a.js', 'node_modules/zeta/b.js'];
  const text = thirdPartyNotices(root, inputs);
  assert.equal(text, thirdPartyNotices(root, inputs.toReversed()));
  assert.equal(text.split('Package: zeta@1.2.3').length, 2);
  assert.ok(text.indexOf('alpha@1.2.3') < text.indexOf('zeta@1.2.3'));
  assert.ok(text.includes('Copyright Z\n  Keep this spacing.\r\n'));
  assert.ok(!text.includes('dev-only'));
});

test('scoped and nested packages retain all notice files with Windows input separators', t => {
  const root = fixture(t, {
    'node_modules/@scope/client': { 'LICENSE-MIT': 'MIT text', 'NOTICE': 'Attribution' },
    'node_modules/client/node_modules/protocol': { 'COPYING': 'Protocol text' },
  });
  const text = thirdPartyNotices(root, [
    'node_modules\\@scope\\client\\dist\\client.js',
    'node_modules/client/node_modules/protocol/lib/index.js',
  ]);
  for (const expected of ['@scope/client@1.2.3', 'protocol@1.2.3', 'MIT text', 'Attribution', 'Protocol text']) {
    assert.ok(text.includes(expected), expected);
  }
});

test('a bundled dependency without a notice blocks packaging', t => {
  const root = fixture(t, { 'node_modules/missing': {} });
  assert.throws(() => thirdPartyNotices(root, ['node_modules/missing/index.js']), /No third-party notice files/);
});

test('empty notice files do not satisfy the package check', t => {
  const root = fixture(t, { 'node_modules/empty': { 'LICENSE': ' \n' } });
  assert.throws(() => thirdPartyNotices(root, ['node_modules/empty/index.js']), /Empty third-party notice/);
});

// Microsoft packages ship these beside License.txt, and esbuild's minifier drops
// their source comments. The combined names must not be mistaken for non-notices.
test('combined third-party and copyright notice filenames are preserved', t => {
  const files = {
    'License.txt': 'Main license',
    'thirdpartynotices.txt': 'Microsoft upstream attributions',
    'ThirdPartyNotice.txt': 'Singular notice',
    'ThirdPartyNotices.txt': 'Plural mixed-case notice',
    'NOTICES': 'Plural standalone notice',
    'THIRD-PARTY-NOTICES.txt': 'Separated notice',
    'CopyrightNotice.txt': 'Additional copyright',
  };
  const root = fixture(t, { 'node_modules/client': files });
  const text = thirdPartyNotices(root, ['node_modules/client/index.js']);
  for (const [name, content] of Object.entries(files)) {
    assert.ok(text.includes(`--- node_modules/client/${name} ---\n${content}`), name);
  }
});

test('the production bundle preserves installed Microsoft third-party attributions', () => {
  const root = path.resolve(__dirname, '..');
  const result = require('node:child_process').spawnSync(process.execPath, ['build.js'], {
    cwd: root, encoding: 'utf8',
  });
  assert.equal(result.status, 0, result.stderr || String(result.error || ''));
  const bundled = fs.readFileSync(path.join(root, 'dist/THIRD-PARTY-NOTICES.txt'));
  for (const name of ['vscode-jsonrpc', 'vscode-languageserver-protocol',
    'vscode-languageserver-textdocument', 'vscode-languageserver-types']) {
    const source = fs.readFileSync(path.join(root, 'node_modules', name, 'thirdpartynotices.txt'));
    assert.ok(bundled.includes(source), `Missing exact upstream attributions for ${name}`);
  }
});
