const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {execFileSync} = require('node:child_process');
const {purePage, embeddedData} = require('./pure-page.cjs');

const root = path.join(__dirname, '../..');
const binary = process.env.MS_BIN
  ? path.resolve(root, process.env.MS_BIN)
  : path.resolve(root, process.env.CARGO_TARGET_DIR || 'target', 'debug', process.platform === 'win32' ? 'ms.exe' : 'ms');
const empty = {f: [], m: [], e: []};

test('enum is highlighted as a keyword', () => {
  const {hl} = purePage(empty);
  assert.equal(hl('enum Choice[T]:'), '<span class="tk-kw">enum</span> <span class="tk-ty">Choice</span>[<span class="tk-ty">T</span>]:');
  assert.equal(hl('enum', true), '<span class="tk-kw">enum</span>');
});

test('case remains an ordinary identifier and quoted keywords stay quoted', () => {
  const {hl} = purePage(empty);
  assert.equal(hl('case(value)'), '<span class="tk-fn">case</span>(value)');
  assert.equal(hl('case: Int'), 'case: <span class="tk-ty">Int</span>');
  assert.equal(hl('case', true), '<span class="id " data-c="0">case</span>');
  assert.equal(hl('"enum case <&>" // enum case'), '<span class="tk-st">&quot;enum case &lt;&amp;&gt;&quot;</span> <span class="tk-cm">// enum case</span>');
});

test('enum signatures preserve escaping and other declaration spellings', () => {
  const {sigOf} = purePage(empty);
  for (const [kind, spelling] of [['alternative', 'enum'], ['type', 'type'], ['interface', 'interface']]) {
    assert.equal(sigOf({kind, name: 'Choice<T&"'}), `<code><span class="tk-kw">${spelling}</span> Choice&lt;T&amp;&quot;</code>`);
  }
  assert.equal(sigOf({kind: 'fn', name: 'case', slots: [{name: 'value', ty: 'String', var: false, ownership: 'borrow'}], result: {ty: 'Int', ownership: 'owned'}}), '<code>case(value: <span class="brw" data-ownership="borrow" title="borrow">String</span>) <span class="own" data-ownership="owned" title="owned">Int</span></code>');
});

test('checked CLI enum facts render bare cases and retain type relationships', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ms-enum-rendering-'));
  try {
    fs.copyFileSync(path.join(__dirname, 'enum-rendering.ms'), path.join(dir, 'main.ms'));
    const page = execFileSync(binary, ['diagram', 'main.ms', '--format', 'html'], {cwd: dir, encoding: 'utf8'});
    const data = embeddedData(page);
    const p = purePage(data, page);
    const choice = p.D.entities.find(e => e.name === 'Choice');
    assert.ok(choice, 'checked enum is present');
    assert.equal(choice.kind, 'alternative');
    assert.deepEqual(choice.slots.map(s => [s.name, s.ty]), [
      ['missing', ''], ['found', '(value: T)'], ['paired', '(left: Item, right: List[T])'],
    ]);
    const box = p.D.entities.find(e => e.name === 'Box');
    assert.ok(box.slots.find(s => s.name === 'choice').refs.includes(choice.key));
    p.S.sel = choice.key;
    const rendered = p.types();
    assert.match(rendered, /<title>enum Choice<\/title>/);
    assert.match(rendered, />enum Choice:<\/text>/);
    assert.match(rendered, />missing<\/text>/);
    assert.match(rendered, />found\(value: T\)<\/text>/);
    assert.match(rendered, />paired\(left: Item, right: List\[T\]\)<\/text>/);
    assert.doesNotMatch(rendered, />case (missing|found|paired)/);
    assert.match(rendered, /<title>type Item<\/title>/);
    assert.match(rendered, /class="edge"/);
    assert.equal(p.sigOf(choice), '<code><span class="tk-kw">enum</span> Choice</code>');
    p.S.sel = box.key;
    const controls = p.types();
    assert.match(controls, /<title>type Box<\/title>/);
    assert.match(controls, /<title>interface Reader<\/title>/);
    assert.match(controls, />case: Int<\/text>/);
    assert.match(controls, />fn read\(\) Int<\/text>/);
    p.S.sel = choice.key;
    choice.name = 'Choice<&"';
    assert.match(p.types(), /<title>enum Choice&lt;&amp;&quot;<\/title>/);
  } finally {
    fs.rmSync(dir, {recursive: true, force: true});
  }
});
