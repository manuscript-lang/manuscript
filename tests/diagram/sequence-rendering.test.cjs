const assert = require('node:assert/strict');
const {test} = require('node:test');
const {purePage} = require('./pure-page.cjs');

const call = i => ['call', `call f${i}()`, i, []];
const note = kind => [kind, kind, -1, []];
function model(flows) {
  const e = flows.map((flow, i) => [0, 'fn', `f${i}`, 1, 0, [], '', 0,
    [], [], [], 0, flow, 1, 2, `f${i}`]);
  const p = purePage({f: ['main.ms'], m: [[0, []]], e});
  return {p, events: (depth = 3, all = false) => p.sequenceEvents(p.D.entities[0], depth, all).ev};
}
const msg = (from, to) => ({t: 'msg', from: `main.ms#fn#f${from}`, to: `main.ms#fn#f${to}`, label: `f${to}()`});
const ret = (from, to) => ({t: 'ret', from: `main.ms#fn#f${from}`, to: `main.ms#fn#f${to}`});

test('leaf and sibling calls each return before the next call', () => {
  const {events} = model([[call(1), call(2)], [], []]);
  assert.deepEqual(events(), [msg(0, 1), ret(1, 0), msg(0, 2), ret(2, 0)]);
});

test('nested calls unwind returns in stack order, including at depth limits', () => {
  const {events} = model([[call(1)], [call(2)], []]);
  assert.deepEqual(events(), [msg(0, 1), msg(1, 2), ret(2, 1), ret(1, 0)]);
  assert.deepEqual(events(1), [msg(0, 1), ret(1, 0)]);
});

test('recursive and mutually recursive calls remain bounded and return', () => {
  assert.deepEqual(model([[call(0)]]).events(4), [msg(0, 0), ret(0, 0)]);
  const {events} = model([[call(1)], [call(0)]]);
  assert.deepEqual(events(4), [msg(0, 1), msg(1, 0), ret(0, 1), ret(1, 0)]);
});

test('callee notes retain a single return and native visibility stays optional', () => {
  const {events} = model([[call(1)], [note('branch'), note('native')]]);
  const branch = {t: 'note', at: 'main.ms#fn#f1', label: 'branch'};
  assert.deepEqual(events(), [msg(0, 1), branch, ret(1, 0)]);
  assert.deepEqual(events(3, true), [msg(0, 1), branch,
    {t: 'msg', from: 'main.ms#fn#f1', to: 'stdlib', label: 'native'}, ret(1, 0)]);
});

test('participant cap keeps calls balanced', () => {
  const many = Array.from({length: 200}, (_, i) => call(i + 1));
  const {p, events} = model([many, ...many.map(() => [])]);
  assert.equal(p.sequenceEvents(p.D.entities[0], 3, false).parts.length, 14);
  const ev = events();
  assert.equal(ev.length, 26);
  for (let i = 0; i < ev.length; i += 2) {
    assert.equal(ev[i].t, 'msg');
    assert.deepEqual(ev[i + 1], {t: 'ret', from: ev[i].to, to: ev[i].from});
  }
});

test('event budget bounds repeated calls and still unwinds nested returns', () => {
  const repeated = Array.from({length: 200}, () => call(2));
  const {events} = model([[call(1)], repeated, []]);
  const ev = events();
  assert.equal(ev.length, 322);
  assert.deepEqual(ev[0], msg(0, 1));
  assert.deepEqual(ev[ev.length - 1], ret(1, 0));
  for (let i = 1; i < ev.length - 1; i += 2) {
    assert.deepEqual(ev[i], msg(1, 2));
    assert.deepEqual(ev[i + 1], ret(2, 1));
  }
});
