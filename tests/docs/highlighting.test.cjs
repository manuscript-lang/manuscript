const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { tokenize: tokenizeWithGrammar } = require('../../website/assets/manuscript-highlight.js');
const grammar = require('../../extensions/vscode/syntaxes/manuscript.tmLanguage.json');
const tokenize = source => tokenizeWithGrammar(source, grammar);
const root = path.resolve(__dirname, '../..');

function assertScopes(source, expected) {
  const tokens = tokenize(source);
  assert.equal(tokens.map(token => token.text).join(''), source);
  const kinds = tokens.flatMap(token => token.text.split('').map(() => token.kind));
  for (const [text, kind] of expected) {
    const start = source.indexOf(text);
    assert.notEqual(start, -1, `Missing fixture text: ${text}`);
    assert.ok(kinds.slice(start, start + text.length).every(actual => actual === kind),
      `${JSON.stringify(text)} should have scope ${kind}`);
  }
  return tokens;
}

test('Manuscript examples receive keyword, type, function, string, and number tokens', () => {
  const source = 'import arguments from "@std/process.ms"\nexport fn main() Int:\n    return 0\n';
  const tokens = tokenize(source);
  const has = (text, kind) => tokens.some(token => token.text === text && token.kind === kind);
  assert.ok(has('import', 'k'));
  assert.ok(has('Int', 'nc'));
  assert.ok(has('main', 'nf'));
  assert.ok(has('"@std/process.ms"', 's'));
  assert.ok(has('0', 'mi'));
  assert.equal(tokens.map(token => token.text).join(''), source);
});

test('comments and strings do not highlight their contents as executable code', () => {
  const source = 'let message = "# return true"\n# fn ignored() Int: return 123\n';
  const tokens = tokenize(source);
  assert.ok(tokens.some(token => token.kind === 's' && token.text === '"# return true"'));
  assert.ok(tokens.some(token => token.kind === 'c1' && token.text === '# fn ignored() Int: return 123'));
  assert.equal(tokens.filter(token => token.kind === 'k').map(token => token.text).join(''), 'let');
});

test('shared grammar keyword rules do not match inside longer or Unicode identifiers', () => {
  const tokens = tokenize('fnord trueish unit_value café fné\n');
  assert.equal(tokens.filter(token => ['k', 'kc'].includes(token.kind)).length, 0);
});

test('strings end before the following code, including interpolations, nested strings and escapes', () => {
  const literals = [
    String.raw`"Hello, {name}!\n"`,
    String.raw`"Hello {format(value: "Ada")} \{literal\} \u{1F600}"`,
    String.raw`"Braces {format(value: "\{")} stay in the nested string"`,
    String.raw`"Nested {format(value: "Hello {names.get(0, default: "Ada")}")}"`,
  ];
  for (const literal of literals) {
    const source = `let message = ${literal}\nreturn 0\n`;
    const tokens = tokenize(source);
    assert.ok(tokens.some(token => token.kind === 's' && token.text.startsWith('"')));
    assert.ok(!tokens.some(token => token.kind === 's' && token.text.includes('return')));
    assert.ok(tokens.some(token => token.kind === 'k' && token.text === 'return'));
    assert.ok(tokens.some(token => token.kind === 'mi' && token.text === '0'));
    assert.equal(tokens.map(token => token.text).join(''), source);
  }
});

test('current boolean spellings are constants; capitalized forms are ordinary names', () => {
  const tokens = tokenize('true false unit True False\n');
  assert.deepEqual(tokens.filter(token => token.kind).map(token => [token.text, token.kind]), [
    ['true', 'kc'], ['false', 'kc'], ['unit', 'kc'], ['True', 'nc'], ['False', 'nc'],
  ]);
});

test('highlighting preserves Unicode, HTML-like strings, decimals, and scientific notation for copying', () => {
  const source = 'let café = "<script>& 🐈</script>"\nlet price = 12.50d\nlet ratio = 1e-3\n';
  const tokens = tokenize(source);
  assert.equal(tokens.map(token => token.text).join(''), source);
  assert.ok(tokens.some(token => token.kind === 'mi' && token.text === '12.50d'));
  assert.ok(tokens.some(token => token.kind === 'mi' && token.text === '1e-3'));
});

test('from is a keyword only on import lines', () => {
  const keywords = source => tokenize(source).filter(token => token.kind === 'k').map(token => token.text);
  assert.deepEqual(keywords('import a, b from "x.ms"\n'), ['import', 'from']);
  assert.deepEqual(keywords('let from = 2\n'), ['let']);
});

test('all compiler keywords have scopes; contextual and retired words stay identifiers', () => {
  const rust = fs.readFileSync(path.join(root, 'crates/ms-syntax/src/token.rs'), 'utf8');
  const keywords = [...rust.match(/pub const KEYWORDS:[\s\S]*?= &\[([\s\S]*?)\];/)[1].matchAll(/"([^"]+)"/g)]
    .map(match => match[1]);
  assert.ok(keywords.length >= 30, 'Read the current compiler keyword inventory');
  for (const word of keywords) {
    assertScopes(word, [[word, ['true', 'false', 'unit'].includes(word) ? 'kc' : 'k']]);
  }
  assertScopes('from as async await null def lambda elif', [
    ['from', ''], ['as', ''], ['async', ''], ['await', ''], ['null', ''],
    ['def', ''], ['lambda', ''], ['elif', ''],
  ]);
  assertScopes('let from = 1\nlet as = 2\nimport Name, value from "x.ms"\n', [
    ['let', 'k'], ['"x.ms"', 's'], ['import', 'k'], ['Name', 'nc'],
  ]);
});

test('compiler symbolic tokens and compound assignments have operator or punctuation scopes', () => {
  const rust = fs.readFileSync(path.join(root, 'crates/ms-syntax/src/token.rs'), 'utf8');
  const symbols = [...rust.matchAll(/\w+ => "([^"\w\s]+)"/g)].map(match => match[1]);
  assert.ok(symbols.length >= 25, 'Read the current compiler symbol inventory');
  for (const symbol of [...symbols, '+=', '-=', '*=', '/=', '%=']) {
    assertScopes(symbol, [[symbol, /^[()[\]{}:,.]$/.test(symbol) ? 'p' : 'o']]);
  }
  assertScopes('not true and false or true\n_', [['not', 'k'], ['and', 'k'], ['or', 'k'], ['_', 'kc']]);
});

test('all current numeric bases, separators, fractions, exponents and Decimal forms are whole tokens', () => {
  const literals = ['0', '42', '1_000_000', '0xFF_FF', '0xdead_BEEF', '0b1010_0101',
    '0.5', '3.141_592', '1_000.50_25', '1e3', '1E+3', '1_000.5_0e-12',
    '1d', '12.50d', '1e-6176d', '1_000.50_25E+2d'];
  for (const literal of literals) assertScopes(literal, [[literal, 'mi']]);
  assertScopes('-0xFF + 0..10\n2.seconds()', [
    ['-', 'o'], ['0xFF', 'mi'], ['+', 'o'], ['..', 'o'], ['10', 'mi'], ['2', 'mi'], ['seconds', 'nf'],
  ]);
  for (const invalid of ['0x', '0b2', '0XFF', '1__2', '1_', '1e1_0', '12cats']) {
    assert.ok(!tokenize(invalid).some(token => token.kind === 'mi'), invalid);
  }
});

test('shared nested rules scope escapes, interpolation expressions and nested strings', () => {
  const source = String.raw`let text = "Hello \{world\} \u{1F600} {format(value: {"key": "{1 + 2}"})}!"` + '\r\nreturn 0 # Ω 🐈\r\n';
  assertScopes(source, [
    ['let', 'k'], ['"Hello ', 's'], [String.raw`\{`, 'se'], [String.raw`\}`, 'se'],
    [String.raw`\u{1F600}`, 'se'], ['format', 'nf'], ['"key"', 's'], ['2', 'mi'], ['+', 'o'],
    ['return', 'k'], ['# Ω 🐈', 'c1'],
  ]);
  const tokens = tokenize(source);
  assert.equal(tokens.filter(token => token.kind === 'si').map(token => token.text).join(''), '{{}}');
  assertScopes(String.raw`"# True \{literal\} \" \\ \n \r \t \u{41}"`, [
    ['# True ', 's'], [String.raw`\"`, 'se'], [String.raw`\\`, 'se'],
    [String.raw`\n`, 'se'], [String.raw`\r`, 'se'], [String.raw`\t`, 'se'], [String.raw`\u{41}`, 'se'],
  ]);
});

test('parser fixture covers declarations, implicit borrows, lambdas and patterns', () => {
  const source = fs.readFileSync(path.join(__dirname, 'syntax.ms'), 'utf8');
  assertScopes(source, [
    ['extern', 'k'], ['type', 'k'], ['Box', 'nc'], ['interface', 'k'], ['Reader', 'nc'],
    ['impl', 'k'], ['identity', 'nf'], ['self', 'k'], ['replace', 'nf'],
    ['var', 'k'], ['let', 'k'], ['fn', 'k'],
    ['match', 'k'], ['case', 'k'], ['Ready', 'nc'],
    ['borrowed', ''], ['exclusive', ''], ['specialized', ''], ['...', 'o'],
  ]);
  assertScopes('fn Uppercase() Int: 1\ntype lowercase: ...\ninterface readable:\n    fn get() String\n', [
    ['Uppercase', 'nf'], ['lowercase', 'nc'], ['readable', 'nc'], ['get', 'nf'],
  ]);
  assertScopes('identity[List[Map[String, Int]]](items)', [['identity', 'nf'], ['List', 'nc'], ['Map', 'nc']]);
});

test('every authored Manuscript fence preserves its exact source text', () => {
  let fences = 0;
  for (const file of fs.readdirSync(path.join(root, 'documentation'), { recursive: true })) {
    if (!file.endsWith('.md')) continue;
    const markdown = fs.readFileSync(path.join(root, 'documentation', file), 'utf8');
    for (const match of markdown.matchAll(/```(?:manuscript|ms)(?:[^\n]*)\n([\s\S]*?)```/g)) {
      assert.equal(tokenize(match[1]).map(token => token.text).join(''), match[1], file);
      fences++;
    }
  }
  assert.ok(fences > 100, 'Discover the current authored examples');
});
