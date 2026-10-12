const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '../..');
const book = process.env.MANUSCRIPT_BOOK_DIR || path.join(root, '.artifacts/book');

function attribute(tag, name) {
  const match = tag.match(new RegExp(`\\b${name}=(?:"([^"]*)"|'([^']*)'|([^\\s>]+))`));
  return match && (match[1] ?? match[2] ?? match[3]);
}

test('published API downloads match the current generated reference', () => {
  for (const file of ['stdlib.json', 'stdlib.md']) {
    assert.equal(
      fs.readFileSync(path.join(book, file), 'utf8'),
      fs.readFileSync(path.join(root, 'website/static', file), 'utf8'),
      `Rebuild the website: ${file} is stale`,
    );
  }
});

test('published API routes contain exactly the current modules', () => {
  const source = path.join(root, 'documentation/standard-library/reference');
  const expected = fs.readdirSync(source)
    .filter(name => name.endsWith('.md') && name !== '_index.md')
    .map(name => name.slice(0, -3)).sort();
  const output = path.join(book, 'standard-library/reference');
  const actual = fs.readdirSync(output, { withFileTypes: true })
    .filter(entry => entry.isDirectory()).map(entry => entry.name).sort();
  assert.deepEqual(actual, expected, 'Rebuild with --cleanDestinationDir to remove obsolete module pages');
  for (const module of expected) {
    assert.ok(fs.existsSync(path.join(output, module, 'index.html')), `Missing page for ${module}`);
  }
});

test('rendered API signatures match the generated module pages', () => {
  const source = path.join(root, 'documentation/standard-library/reference');
  const entities = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", '#34': '"', '#39': "'" };
  for (const file of fs.readdirSync(source).filter(name => name.endsWith('.md') && name !== '_index.md')) {
    const markdown = fs.readFileSync(path.join(source, file), 'utf8');
    const expected = [...markdown.matchAll(/```manuscript\n([\s\S]*?)```/g)].map(match => match[1].trimEnd());
    const html = fs.readFileSync(path.join(book, 'standard-library/reference', file.slice(0, -3), 'index.html'), 'utf8');
    const actual = [...html.matchAll(/<pre\b[^>]*><code\b[^>]*>([\s\S]*?)<\/code><\/pre>/g)]
      .map(match => match[1].replace(/&(amp|lt|gt|quot|apos|#34|#39);/g, (_, entity) => entities[entity]).trimEnd());
    assert.deepEqual(actual, expected, `Rebuild the website: ${file} has stale API signatures`);
  }
});

test('published internal links and anchors resolve under the site prefix', () => {
  const html = new Map();
  function visit(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const file = path.join(directory, entry.name);
      if (entry.isDirectory()) visit(file);
      else if (entry.name.endsWith('.html')) html.set(file, fs.readFileSync(file, 'utf8'));
    }
  }
  visit(book);
  const home = html.get(path.join(book, 'index.html'));
  const canonical = [...home.matchAll(/<link\b[^>]*>/g)]
    .map(match => match[0]).find(tag => attribute(tag, 'rel') === 'canonical');
  assert.ok(canonical, 'Home page needs a canonical URL');
  const prefix = new URL(attribute(canonical, 'href')).pathname;
  const ids = new Map([...html].map(([file, text]) => [file, new Set(
    [...text.matchAll(/<[^>]+>/g)].map(match => attribute(match[0], 'id')).filter(Boolean),
  )]));
  const failures = [];
  for (const [file, text] of html) {
    for (const match of text.matchAll(/<a\b[^>]*>/g)) {
      const raw = attribute(match[0], 'href');
      if (raw === null) continue;
      const href = raw.replaceAll('&amp;', '&');
      if (/^(?:[a-z][a-z0-9+.-]*:|\/\/)/i.test(href)) continue;
      const relative = path.relative(book, file).split(path.sep).join('/');
      const url = new URL(href, `https://example.org${prefix}${relative}`);
      if (!url.pathname.startsWith(prefix)) {
        failures.push(`${relative}: ${href} escapes the site prefix`);
        continue;
      }
      let target = path.join(book, decodeURIComponent(url.pathname.slice(prefix.length)));
      if (fs.existsSync(target) && fs.statSync(target).isDirectory()) target = path.join(target, 'index.html');
      if (!fs.existsSync(target)) failures.push(`${relative}: ${href} has no target`);
      else if (url.hash && ids.has(target) && !ids.get(target).has(decodeURIComponent(url.hash.slice(1)))) {
        failures.push(`${relative}: ${href} has no anchor`);
      }
    }
  }
  assert.deepEqual(failures, []);
});

test('previous and next links follow the rendered sidebar reading order', () => {
  const home = fs.readFileSync(path.join(book, 'index.html'), 'utf8');
  const canonical = [...home.matchAll(/<link\b[^>]*>/g)]
    .map(match => match[0]).find(tag => attribute(tag, 'rel') === 'canonical');
  const prefix = new URL(attribute(canonical, 'href')).pathname;
  const nav = home.match(/<nav\b[^>]*aria-label=(?:"Documentation"|'Documentation'|Documentation)[^>]*>[\s\S]*?<\/nav>/)[0];
  const groups = [...nav.matchAll(/<div\b[^>]*class=(?:"nav-group"|'nav-group'|nav-group)[^>]*>([\s\S]*?)<\/div>/g)];
  const routes = groups.flatMap(group => [...group[1].matchAll(/<a\b[^>]*>/g)]
    .map(match => attribute(match[0], 'href')));
  assert.ok(routes.length > 0, 'The sidebar must expose a reading path');
  assert.equal(new Set(routes).size, routes.length, 'Each page belongs to one sidebar position');

  for (const [index, route] of routes.entries()) {
    const file = path.join(book, route.slice(prefix.length), 'index.html');
    const html = fs.readFileSync(file, 'utf8');
    const footer = html.match(/<footer\b[^>]*>[\s\S]*?<\/footer>/)[0];
    const links = [...footer.matchAll(/<a\b[^>]*>/g)].map(match => match[0]);
    for (const [rel, expected] of [['prev', routes[index - 1]], ['next', routes[index + 1]]]) {
      const tag = links.find(link => attribute(link, 'rel') === rel);
      assert.equal(tag && attribute(tag, 'href') || undefined, expected, `${route}: ${rel} skips the sidebar order`);
    }
  }
});
