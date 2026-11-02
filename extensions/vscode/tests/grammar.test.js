const { test } = require('node:test');
const assert = require('node:assert/strict');
const grammar = require('../syntaxes/manuscript.tmLanguage.json');

test('strings scope escapes and nest interpolation with nested strings', () => {
  const string = grammar.repository.string;
  assert.equal(grammar.patterns.filter(p => p.include === '#string').length, 1);
  const escape = new RegExp(string.patterns.find(p => p.name === 'constant.character.escape.manuscript').match);
  for (const ok of ['\\n', '\\"', '\\{', '\\}', '\\u{41}', '\\u{10FFFF}']) assert.ok(escape.test(ok), ok);
  for (const bad of ['\\q', '\\u41']) assert.ok(!escape.test(bad), bad);
  // An interpolation may contain further strings (the lexer scans them recursively),
  // so it must include the whole grammar rather than ending the outer string at an inner quote.
  const interpolation = string.patterns.find(p => p.name === 'meta.interpolation.manuscript');
  assert.equal(interpolation.begin, '\\{');
  assert.equal(interpolation.end, '\\}');
  assert.ok(interpolation.patterns.some(p => p.include === '$self'));
});

test('opaque is a keyword only before type', () => {
  const rule = grammar.patterns.find(p => p.name === 'keyword.control.manuscript' && p.match.startsWith('\\bopaque'));
  const opaque = new RegExp(rule.match);
  assert.ok(opaque.test('export opaque type Token:'));
  assert.ok(!opaque.test('fn opaque(x: Int) Int:'));
});

test('multi-line and raw strings are scoped before the one-line rule', () => {
  const order = grammar.patterns.map(p => p.include).filter(Boolean);
  assert.deepEqual(order.slice(0, 3), ['#raw-multiline-string', '#multiline-string', '#string']);
  const multiline = grammar.repository['multiline-string'];
  assert.equal(multiline.begin, '"""');
  assert.ok(multiline.patterns.some(p => p.name === 'meta.interpolation.manuscript'));
  const raw = grammar.repository['raw-multiline-string'];
  assert.equal(raw.begin, 'r"""');
  assert.equal(raw.patterns, undefined);
});
