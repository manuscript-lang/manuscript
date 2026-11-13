const assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {after, test} = require('node:test');
const {purePage, embeddedData} = require('./pure-page.cjs');

const root = path.resolve(__dirname, '../..');
const binary = process.env.MS_BIN
  ? path.resolve(root, process.env.MS_BIN)
  : path.resolve(root, process.env.CARGO_TARGET_DIR || 'target', 'debug', process.platform === 'win32' ? 'ms.exe' : 'ms');
const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'ms-html-ownership-'));
after(() => fs.rmSync(fixture, {recursive: true, force: true}));
fs.copyFileSync(path.join(root, 'crates/ms-cli/tests/ownership_modes/main.ms'), path.join(fixture, 'main.ms'));
const run = args => execFileSync(binary, ['diagram', 'main.ms', ...args], {cwd: fixture, encoding: 'utf8'});
const page = run(['--format', 'html']);
const data = embeddedData(page);
const p = purePage(data, page);
const artifactDir = process.env.MS_HTML_TEST_ARTIFACTS;
if (artifactDir) {
  fs.mkdirSync(artifactDir, {recursive: true});
  fs.copyFileSync(path.join(fixture, 'main.ms'), path.join(artifactDir, 'ownership-main.ms'));
  fs.writeFileSync(path.join(artifactDir, 'ownership.html'), page);
  fs.writeFileSync(path.join(artifactDir, 'ownership-data.json'), JSON.stringify(data, null, 2));
}
const callables = p.D.entities.filter(e => e.kind === 'fn' || e.kind === 'method');
const oracles = new Map(callables.map(e => {
  const json = run(['--view', 'ownership', '--entity', e.key, '--json']);
  const mermaid = run(['--view', 'ownership', '--entity', e.key, '--format', 'mermaid']);
  if (artifactDir) {
    const name = data.e[p.D.entities.indexOf(e)][2];
    fs.writeFileSync(path.join(artifactDir, name + '.json'), json);
    fs.writeFileSync(path.join(artifactDir, name + '.mmd'), mermaid);
  }
  return [e.key, {labels: JSON.parse(json).tree.children[0].children.map(n => n.label), mermaid}];
}));

test('HTML explicit parameter and result modes agree with checked JSON and Mermaid', () => {
  const seen = new Set();
  for (const e of callables) {
    const raw = data.e[p.D.entities.indexOf(e)];
    const {labels, mermaid} = oracles.get(e.key);
    e.slots.forEach((slot, i) => {
      const label = labels[i];
      assert.ok(label.startsWith(slot.name + ': ' + slot.ty + '  '), label);
      const mode = label.slice(label.lastIndexOf('  ') + 2).replace(' (exclusive borrow)', '');
      assert.equal(raw[10][i][4], mode, e.key + ' compact parameter');
      assert.equal(slot.ownership, mode, e.key + ' decoded parameter');
      assert.ok(mermaid.includes('|"' + slot.name + ' ' + mode + '"|'), mermaid);
      seen.add(mode);
    });
    const result = labels[e.slots.length];
    assert.ok(result.startsWith('returns ' + e.result.ty + '  '), result);
    const mode = result.slice(result.lastIndexOf('  ') + 2);
    assert.equal(raw[11][2], mode, e.key + ' compact result');
    assert.equal(e.result.ownership, mode, e.key + ' decoded result');
    assert.ok(mermaid.includes('|"' + mode + '"|'), mermaid);
    seen.add(mode);
  }
  assert.deepEqual([...seen].sort(), ['borrow', 'copy', 'move', 'owned', 'owned view', 'owned; borrowed error', 'owned; borrowed ok', 'var'].sort());
});

test('signature type spans expose exact checked modes with the existing palette', () => {
  const palette = {borrow: 'brw', copy: 'hint', move: 'own', var: 'var', owned: 'own',
    'owned view': 'own', 'owned; borrowed ok': 'own', 'owned; borrowed error': 'own'};
  for (const e of callables) {
    const spans = [...p.sigOf(e).matchAll(/<span class="([^"]*)" data-ownership="([^"]*)" title="([^"]*)">([^<]*)<\/span>/g)];
    const positions = [...e.slots, e.result];
    assert.equal(spans.length, positions.length, e.key);
    positions.forEach((position, i) => {
      assert.equal(spans[i][1], palette[position.ownership], e.key);
      assert.equal(spans[i][2], position.ownership, e.key);
      assert.equal(spans[i][3], position.ownership, e.key);
    });
    const plain = e.name + '(' + e.slots.map(s => (s.var ? 'var ' : '') + s.name + ': ' + s.ty).join(', ') + ') ' + e.result.ty;
    assert.equal(p.sigOf(e).replace(/<[^>]*>/g, ''), plain, e.key + ' signature text');
  }
});

test('missing and unknown modes stay neutral and type and attribute text stays escaped', () => {
  const signature = mode => p.sigOf({kind: 'fn', name: 'show<&"',
    slots: [{name: 'value<&"', ty: 'Value<&"', var: false, ownership: mode}],
    result: {ty: 'Result<&"', ownership: mode}});
  assert.equal(signature(undefined), '<code>show&lt;&amp;&quot;(value&lt;&amp;&quot;: <span>Value&lt;&amp;&quot;</span>) <span>Result&lt;&amp;&quot;</span></code>');
  const unknown = signature('unknown<&"');
  assert.doesNotMatch(unknown, /class="(brw|own|var|hint)"/);
  assert.match(unknown, /data-ownership="unknown&lt;&amp;&quot;" title="unknown&lt;&amp;&quot;"/);
  assert.match(unknown, />Value&lt;&amp;&quot;<\/span>/);
  assert.match(signature('owned; borrowed ok and error'), /class="own" data-ownership="owned; borrowed ok and error"/);
});

test('noncallable arrays, reference indexes and unrelated pure rendering stay unchanged', () => {
  const stripped = structuredClone(data);
  for (const row of stripped.e) {
    for (const slot of row[10]) slot.length = 4;
    if (row[11]) row[11].length = 2;
  }
  const withoutModes = purePage(stripped, page);
  for (let i = 0; i < data.e.length; i++) {
    const row = data.e[i], e = p.D.entities[i];
    if (!['fn', 'method'].includes(row[1])) assert.deepEqual(row, stripped.e[i], e.key);
    row[10].forEach((slot, j) => assert.deepEqual(slot[3].map(k => p.D.entities[k].key), e.slots[j].refs));
    if (row[11]) assert.deepEqual(row[11][1].map(k => p.D.entities[k].key), e.result.refs);
    if (!['type', 'alternative', 'interface'].includes(row[1])) continue;
    p.S.sel = e.key;
    withoutModes.S.sel = e.key;
    assert.equal(p.types(), withoutModes.types(), e.key + ' type graph');
    assert.equal(p.sigOf(e), withoutModes.sigOf(withoutModes.D.entities[i]));
  }
  assert.equal(p.hl('enum Choice: // ownership'), withoutModes.hl('enum Choice: // ownership'));
});
