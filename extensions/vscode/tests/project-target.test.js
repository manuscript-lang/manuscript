const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { targetFor } = require('../project-target');

test('project lookup selects the nearest manifest, even if it is invalid', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'manuscript project '));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const nested = path.join(root, 'nested');
  await fs.mkdir(path.join(nested, 'src'), { recursive: true });
  const outerManifest = path.join(root, 'ms.toml');
  const innerManifest = path.join(nested, 'ms.toml');
  const source = path.join(nested, 'src', 'main.ms');
  await fs.writeFile(outerManifest, '[project]');
  assert.equal(await targetFor(source), outerManifest);
  await fs.writeFile(innerManifest, 'invalid manifest');
  assert.equal(await targetFor(source), innerManifest);
});

test('project lookup falls back to the source at the filesystem root', async () => {
  const root = path.parse(process.cwd()).root;
  const source = path.join(root, 'one', 'two', 'main.ms');
  const checked = [];
  // A missing manifest is the only error that permits fallback.
  const access = fs.access;
  fs.access = async manifest => { checked.push(manifest); throw Object.assign(new Error('missing'), { code: 'ENOENT' }); };
  try {
    assert.equal(await targetFor(source), source);
    assert.deepEqual(checked, [path.join(root, 'one', 'two', 'ms.toml'), path.join(root, 'one', 'ms.toml'), path.join(root, 'ms.toml')]);
  }
  finally { fs.access = access; }
});

test('project lookup propagates access errors instead of selecting a parent', async () => {
  const access = fs.access;
  const denied = Object.assign(new Error('denied'), { code: 'EACCES' });
  fs.access = async () => { throw denied; };
  try { await assert.rejects(targetFor(path.resolve('main.ms')), error => error === denied); }
  finally { fs.access = access; }
});
