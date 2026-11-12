const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {test} = require('node:test');
const page = fs.readFileSync(path.join(__dirname, '../../crates/ms-tooling/src/page.html'), 'utf8');
const start = page.indexOf('function route(){'), end = page.indexOf('const VIEWS=', start);
assert.ok(start >= 0 && end > start);
const route = new Function('E', 'S', 'esc', 'empty', page.slice(start, end) + 'return route();');
const escape = text => text.replace(/[&<>"]/g, c => ({'&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;'}[c]));
const render = (entities, from, to) => route(entities, {from, to}, escape, (title, text) => title + text);
const steps = html => [...html.matchAll(/class="step" data-key="([^"]+)"/g)].map(m => m[1]);

test('route keeps shortest-path ties, cycles, duplicate edges and escaped labels', () => {
  const entities = {a:{name:'a<&"',calls:['b','c','b']}, b:{name:'b',calls:['a','d']}, c:{name:'c',calls:['d']}, d:{name:'d',calls:[]}, z:{name:'z',calls:[]}};
  assert.deepEqual(steps(render(entities, 'a', 'd')), ['a','b','d']);
  assert.deepEqual(steps(render(entities, 'a', 'a')), ['a']);
  assert.match(render(entities, 'a', 'z'), /No call path/);
  assert.match(render(entities, 'a', 'd'), /a&lt;&amp;&quot;/);
});

test('route reaches the last branch of a wide frontier', () => {
  const entities = {root:{name:'root',calls:[]}, end:{name:'end',calls:[]}};
  for (let i = 0; i < 20000; i++) {
    const key = `n${i}`;
    entities.root.calls.push(key);
    entities[key] = {name:key,calls:i === 19999 ? ['end'] : []};
  }
  assert.deepEqual(steps(render(entities, 'root', 'end')), ['root','n19999','end']);
});
