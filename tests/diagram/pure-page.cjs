const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const template = fs.readFileSync(path.join(__dirname, '../../crates/ms-tooling/src/page.html'), 'utf8');

function between(source, start, end) {
  const first = source.indexOf(start);
  assert.notEqual(first, -1, `missing pure helper start: ${start}`);
  const last = source.indexOf(end, first + start.length);
  assert.notEqual(last, -1, `missing pure helper end: ${end}`);
  return source.slice(first, last);
}

// Evaluate only data decoding and pure string-rendering functions. In particular,
// this does not run page startup or provide a document, browser, or DOM substitute.
function purePage(data, source = template) {
  const code = [
    between(source, 'const D={', 'const $='),
    between(source, 'const esc=', 'const KI='),
    between(source, 'const KW=', '/* checked types'),
    between(source, 'function sigOf(', 'const fns='),
    between(source, 'function stage(', 'const fcls='),
    between(source, 'function types(){', '/* sequence:'),
    between(source, 'const empty=', 'function behavior('),
    'return {D,E,S,hl,sigOf,types};',
  ].join('\n');
  return new Function('R', code)(data);
}

function embeddedData(page) {
  const match = page.match(/<script id="data" type="application\/json">([\s\S]*?)<\/script>/);
  assert.ok(match, 'CLI HTML contains compact program data');
  const normalized = page.replace(match[0], '<script id="data" type="application/json">__DATA__</script>');
  assert.ok(normalized.trimEnd() === template.trimEnd(), 'CLI HTML uses this checkout\'s production page template');
  return JSON.parse(match[1]);
}

module.exports = {purePage, embeddedData};
