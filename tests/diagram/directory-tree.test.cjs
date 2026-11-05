const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { after, test } = require('node:test');
const vm = require('node:vm');

const root = path.resolve(__dirname, '../..');
const page = fs.readFileSync(path.join(root, 'crates/ms-tooling/src/page.html'), 'utf8');
const cli = process.env.MS_BIN
  ? path.resolve(root, process.env.MS_BIN)
  : path.resolve(root, process.env.CARGO_TARGET_DIR || 'target', 'debug', process.platform === 'win32' ? 'ms.exe' : 'ms');
const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'ms-html-directories-'));
after(() => fs.rmSync(fixture, { recursive: true, force: true }));

// All filesystem names here are valid on Linux, macOS and Windows. Quotes and
// angle brackets are covered separately as model inputs, without creating files.
const collisionNames = ['constructor', '__proto__', 'toString', 'hasOwnProperty', 'valueOf'];
const ordinary = ['alpha/a.ms', 'alpha/child/b.ms', 'alphabet/c.ms', 'zeta/z.ms', 'root.ms'];
const collisions = collisionNames.flatMap(name => [
  `${name}/top.ms`, `ordinary/${name}/nested.ms`, `${name}/${name}/deep.ms`,
]);
const escaped = ['space & apostrophe\'/é😀/file & name.ms'];
const directories = Array.from({ length: 151 }, (_, i) => `large/d${String(i).padStart(3, '0')}/file.ms`);
const files = Array.from({ length: 151 }, (_, i) => `many/f${String(i).padStart(3, '0')}.ms`);
const names = [...ordinary, ...collisions, ...escaped, ...directories, ...files];
fs.writeFileSync(path.join(fixture, 'ms.toml'), '[project]\nname = "html-directory-tree"\nsource = "."\nentry = "main.ms"\n');
for (const [i, name] of names.entries()) {
  const file = path.join(fixture, name);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `export fn value_${i}() Int:\n    return ${i}\n`);
}
fs.appendFileSync(path.join(fixture, 'alpha/a.ms'), '\ntest "ordinary test":\n    let _n = 1\n\nbench "ordinary bench":\n    let _n = 1\n');
fs.writeFileSync(path.join(fixture, 'main.ms'), names.map((name, i) =>
  `import value_${i} from ${JSON.stringify('./' + name)}`
).join('\n') + '\n\nexport fn main() Int:\n    return 0\n');
const output = path.join(fixture, 'map.html');
const generated = spawnSync(cli, ['diagram', 'ms.toml', '--format', 'html', '-o', output], {
  cwd: fixture, encoding: 'utf8', timeout: 120_000,
});
assert.ifError(generated.error);
assert.equal(generated.status, 0, generated.stderr);
assert.equal(generated.stdout, '');
const html = fs.readFileSync(output, 'utf8');
const encodedData = html.match(/<script id="data" type="application\/json">([\s\S]*?)<\/script>/)[1];
const data = JSON.parse(encodedData);
const modules = data.m.map(m => ({ file: data.f[m[0]], imports: m[1] }));
if (process.env.MS_HTML_TEST_ARTIFACTS) {
  fs.mkdirSync(process.env.MS_HTML_TEST_ARTIFACTS, { recursive: true });
  fs.writeFileSync(path.join(process.env.MS_HTML_TEST_ARTIFACTS, 'map.html'), html);
  fs.writeFileSync(path.join(process.env.MS_HTML_TEST_ARTIFACTS, 'modules.json'), JSON.stringify(modules, null, 2) + '\n');
}

function between(source, start, end) {
  const first = source.indexOf(start);
  assert.notEqual(first, -1, `missing production start: ${start}`);
  const last = source.indexOf(end, first);
  assert.notEqual(last, -1, `missing production end: ${end}`);
  return source.slice(first, last);
}

// Evaluate only the production model builder and string-rendering functions.
// This never boots the page, creates a document, or simulates browser APIs.
function model(input) {
  const context = vm.createContext({ R: data, input, S: { sel: null, mod: null }, STAR: new Set() });
  const code = [
    between(page, 'const D=', 'const E='),
    'D.modules=input;D.entities=D.entities.filter(e=>input.some(m=>m.file===e.file));',
    between(page, 'const esc=', 'const KW='),
    between(page, 'const base=', 'const fx='),
    between(page, 'const byFile=', 'function sigOf('),
    between(page, 'const KF=', 'const TREE='),
    'const prototypeBefore=Object.getOwnPropertyNames(Object.prototype);',
    between(page, 'const TREE=', 'const KIND_BTNS='),
    '({TREE,OPEN,CAP,reveal,prototypeBefore,prototypeAfter:Object.getOwnPropertyNames(Object.prototype),render:()=>treeHTML(TREE,0)})',
  ].join('\n');
  return vm.runInContext(code, context);
}

function selected(names) {
  const wanted = new Set(names);
  const found = modules.filter(m => wanted.has(m.file));
  assert.equal(found.length, names.length, 'CLI must retain every requested module path');
  return found;
}

function allFiles(node) {
  return [...node.files, ...Object.values(node.dirs).flatMap(allFiles)].sort();
}

function rows(markup, attribute) {
  return [...markup.matchAll(new RegExp(` ${attribute}="([^"]*)"`, 'g'))].map(m => m[1]);
}

test('emitted page contains the current complete production template', () => {
  assert.equal(html.replace(encodedData, '__DATA__'), page);
});

test('CLI module paths preserve valid directory names and deterministic order', () => {
  const actual = modules.map(m => m.file);
  assert.deepEqual(actual, [...names, 'main.ms'].sort());
  assert.equal(new Set(actual).size, actual.length);
  assert.ok(data.e.length >= names.length);
});

test('ordinary directories retain nesting, sibling prefixes, files, and initial expansion', () => {
  const m = model(selected(ordinary));
  assert.deepEqual(allFiles(m.TREE), ordinary.slice().sort());
  assert.deepEqual(rows(m.render(), 'data-tg').filter(f => f.endsWith('/')), ['alpha/', 'alpha/child/', 'alphabet/', 'zeta/']);
  assert.deepEqual(rows(m.render(), 'data-mod'), ['alpha/a.ms', 'alphabet/c.ms', 'zeta/z.ms', 'root.ms']);
  assert.equal(m.OPEN.has('alpha/child/'), false);
  m.reveal('alpha/child/b.ms');
  assert.equal(m.OPEN.has('alpha/'), true);
  assert.equal(m.OPEN.has('alpha/child/'), true);
  assert.ok(rows(m.render(), 'data-mod').includes('alpha/child/b.ms'));
});

test('ordinary file expansion retains functions and grouped tests and benches', () => {
  const m = model(selected(ordinary));
  m.reveal('alpha/a.ms');
  const collapsed = m.render();
  assert.ok(collapsed.includes('>value_0</div>'));
  assert.ok(collapsed.includes('tests and benches (2)'));
  assert.ok(!collapsed.includes('>ordinary test</div>'));
  m.reveal('alpha/a.ms', true);
  const expanded = m.render();
  assert.ok(expanded.includes('>ordinary test</div>'));
  assert.ok(expanded.includes('>ordinary bench</div>'));
});

for (const name of collisionNames) {
  test(`directory ${name} remains distinct at root and nested levels`, () => {
    const input = selected(collisions.filter(file => file.split('/').includes(name)));
    const m = model(input);
    assert.deepEqual(allFiles(m.TREE), input.map(m => m.file).sort());
    const top = m.TREE.dirs[name];
    assert.equal(top.name, name);
    assert.equal(top.path, name + '/');
    assert.equal(top.dirs[name].path, `${name}/${name}/`);
    assert.equal(m.TREE.dirs.ordinary.dirs[name].path, `ordinary/${name}/`);
    m.reveal(`${name}/${name}/deep.ms`);
    m.reveal(`ordinary/${name}/nested.ms`);
    const rendered = m.render();
    assert.ok(rows(rendered, 'data-mod').includes(`${name}/${name}/deep.ms`));
    assert.ok(rows(rendered, 'data-mod').includes(`ordinary/${name}/nested.ms`));
  });
}

test('mixed directory keys do not lose siblings or alter Object.prototype', () => {
  const m = model(selected([...ordinary, ...collisions]));
  assert.deepEqual(allFiles(m.TREE), [...ordinary, ...collisions].sort());
  assert.deepEqual([...m.prototypeAfter], [...m.prototypeBefore]);
  assert.equal(m.TREE.dirs.constructor.files[0], 'constructor/top.ms');
  assert.equal(m.TREE.dirs.__proto__.files[0], '__proto__/top.ms');
});

test('CLI Unicode and escaped names keep exact labels and attribute paths', () => {
  const m = model(selected(escaped));
  m.reveal(escaped[0]);
  const rendered = m.render();
  assert.ok(rendered.includes('data-tg="space &amp; apostrophe\'/é😀/"'));
  assert.ok(rendered.includes('>space &amp; apostrophe\'/</div>'));
  assert.ok(rendered.includes('data-mod="space &amp; apostrophe\'/é😀/file &amp; name.ms"'));
  assert.ok(rendered.includes('>file &amp; name.ms</div>'));
});

test('HTML-sensitive model names are escaped in labels and attributes', () => {
  const file = 'constructor/a"<&>/file"<&>.ms';
  const m = model([{ file }]);
  m.reveal(file);
  const rendered = m.render();
  assert.ok(rendered.includes('data-tg="constructor/a&quot;&lt;&amp;&gt;/"'));
  assert.ok(rendered.includes('>a&quot;&lt;&amp;&gt;/</div>'));
  assert.ok(rendered.includes('data-mod="constructor/a&quot;&lt;&amp;&gt;/file&quot;&lt;&amp;&gt;.ms"'));
});

test('large CLI directory list retains all data and caps sorted visible children at 150', () => {
  const m = model(selected(directories));
  assert.equal(Object.values(m.TREE.dirs.large.dirs).length, 151);
  assert.deepEqual(allFiles(m.TREE), directories);
  const rendered = m.render();
  const displayed = rows(rendered, 'data-tg').filter(f => /^large\/d\d+\/$/.test(f));
  assert.deepEqual(displayed, directories.slice(0, 150).map(f => f.slice(0, f.lastIndexOf('/') + 1)));
  assert.ok(rendered.includes('more - use the filter'));
  assert.ok(!rendered.includes('data-tg="large/d150/"'));
});

test('large CLI file list keeps original module order and existing file cap', () => {
  const m = model(selected(files));
  assert.deepEqual(allFiles(m.TREE), files);
  assert.deepEqual(rows(m.render(), 'data-mod'), files.slice(0, 150));
  assert.ok(m.render().includes('more - use the filter'));
});

test('numeric and case-distinct keys preserve current sorted directory rendering', () => {
  const input = ['10/a.ms', '2/b.ms', 'A/c.ms', 'a/d.ms', 'constructor/e.ms'];
  const m = model(input.map(file => ({ file })));
  assert.deepEqual(rows(m.render(), 'data-tg').filter(f => f.endsWith('/')), ['10/', '2/', 'A/', 'a/', 'constructor/']);
});
