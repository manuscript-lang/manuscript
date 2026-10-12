const assert = require('node:assert/strict');
const test = require('node:test');
const { tokenize: tokenizeWithGrammar } = require('../../assets/manuscript-highlight.js');
const grammar = require('../../extensions/vscode/syntaxes/manuscript.tmLanguage.json');
const tokenize = source => tokenizeWithGrammar(source, grammar);

test('Manuscript examples receive keyword, type, function, string, and number tokens', () => {
  const source = 'import Process from "@std/cli.ms"\nexport fn main(process: Process) -> Int:\n    return 0\n';
  const tokens = tokenize(source);
  const has = (text, kind) => tokens.some(token => token.text === text && token.kind === kind);
  assert.ok(has('import', 'k'));
  assert.ok(has('Process', 'nc'));
  assert.ok(has('main', 'nf'));
  assert.ok(has('"@std/cli.ms"', 's'));
  assert.ok(has('0', 'mi'));
  assert.equal(tokens.map(token => token.text).join(''), source);
});

test('comments and strings do not highlight their contents as executable code', () => {
  const source = 'let message = "# return true"\n# fn ignored() -> Int: return 123\n';
  const tokens = tokenize(source);
  assert.ok(tokens.some(token => token.kind === 's' && token.text === '"# return true"'));
  assert.ok(tokens.some(token => token.kind === 'c1' && token.text === '# fn ignored() -> Int: return 123'));
  assert.equal(tokens.filter(token => token.kind === 'k').map(token => token.text).join(''), 'let');
});

test('shared grammar keyword rules do not match inside longer or Unicode identifiers', () => {
  const tokens = tokenize('fnord trueish unit_value café fné\n');
  assert.equal(tokens.filter(token => ['k', 'kc'].includes(token.kind)).length, 0);
});

test('nested interpolation, escaped braces, and Unicode escapes remain one string', () => {
  const literal = String.raw`"Hello {format(value: "Ada")} \{literal\} \u{1F600}"`;
  const source = `let message = ${literal}\nreturn message\n`;
  const tokens = tokenize(source);
  assert.equal(tokens.find(token => token.kind === 's').text, literal);
  assert.ok(tokens.some(token => token.kind === 'k' && token.text === 'return'));
  assert.equal(tokens.map(token => token.text).join(''), source);
});

test('highlighting preserves Unicode, HTML-like strings, decimals, and scientific notation for copying', () => {
  const source = 'let café = "<script>& 🐈</script>"\nlet price = 12.50d\nlet ratio = 1e-3\n';
  const tokens = tokenize(source);
  assert.equal(tokens.map(token => token.text).join(''), source);
  assert.ok(tokens.some(token => token.kind === 'mi' && token.text === '12.50d'));
  assert.ok(tokens.some(token => token.kind === 'mi' && token.text === '1e-3'));
});
