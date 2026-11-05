const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '../..');
const book = process.env.MANUSCRIPT_BOOK_DIR || path.join(root, '.artifacts/book');

function attribute(tag, name) {
  const match = tag.match(new RegExp(`\\b${name}=(?:"([^"]*)"|'([^']*)'|([^\\s>]+))`));
  return match && (match[1] ?? match[2] ?? match[3]);
}

test('the published browser bundle highlights the landing example and current syntax without changing text', () => {
  const html = fs.readFileSync(path.join(book, 'index.html'), 'utf8');
  const script = [...html.matchAll(/<script\b[^>]*>/g)].map(match => attribute(match[0], 'src'))
    .find(src => src && /\/docs\.min\.[^/]+\.js$/.test(src));
  assert.ok(script, 'Load the fingerprinted documentation bundle');
  const entities = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", '#34': '"', '#39': "'" };
  const source = html.match(/<pre\b[^>]*><code\b[^>]*>([\s\S]*?)<\/code><\/pre>/)[1]
    .replace(/&(amp|lt|gt|quot|apos|#34|#39);/g, (_, entity) => entities[entity]);
  const sources = [source, fs.readFileSync(path.join(__dirname, 'syntax.ms'), 'utf8')];
  const classes = sources.map(() => new Set());
  const output = [];
  const codes = sources.map((textContent, index) => ({
    textContent,
    classList: { add: name => classes[index].add(name) },
    replaceChildren: fragment => { output[index] = fragment.children; },
  }));
  const document = {
    documentElement: { dataset: {} },
    querySelector: () => null,
    querySelectorAll: selector => selector.includes('[data-language=') ? codes : [],
    addEventListener() {},
    createDocumentFragment: () => ({ children: [], append(node) { this.children.push(node); } }),
    createElement: () => ({}),
    createTextNode: textContent => ({ textContent }),
  };
  vm.runInNewContext(fs.readFileSync(path.join(book, path.basename(script)), 'utf8'), {
    document,
    window: { matchMedia: () => ({ matches: false, addEventListener() {} }) },
    localStorage: { getItem: () => null },
  });
  for (const [index, source] of sources.entries()) {
    assert.ok(classes[index].has('chroma'));
    assert.equal(output[index].map(node => node.textContent).join(''), source, 'Copy must retain the original source');
  }
  const [rendered, syntax] = output;
  for (const name of ['serve', 'buffered', 'text', 'wait', 'is_ok']) {
    assert.ok(rendered.some(node => node.textContent === name), `Highlight the real homepage call ${name}`);
  }
  assert.ok(rendered.some(node => node.className === 's' && node.textContent === '":8080"'),
    'The listen address must receive string styling');
  assert.equal(rendered.filter(node => node.className === 'k' && node.textContent === 'return').length, 2,
    'The handler and entrypoint returns retains keyword styling');
  for (const kind of ['k', 'kc', 'nc', 'nf', 'mi', 'o', 'p', 's', 'se', 'si', 'c1']) {
    assert.ok(syntax.some(node => node.className === kind), `Missing current-syntax scope ${kind}`);
  }
  for (const literal of ['0xFF_FF', '0b1010_0101', '1_000_000', '3.141_592e-2', '1_000.50_25E+2d']) {
    assert.ok(syntax.some(node => node.className === 'mi' && node.textContent === literal), literal);
  }
});

test('published API downloads match the current generated reference', () => {
  for (const file of ['stdlib.json', 'stdlib.md']) {
    assert.equal(
      fs.readFileSync(path.join(book, file), 'utf8'),
      fs.readFileSync(path.join(root, 'website/static', file), 'utf8'),
      `Rebuild the website: ${file} is stale`,
    );
  }
});

function referenceRoute(file, markdown) {
  const urlPath = file.replaceAll('\\', '/');
  return markdown.match(/url = "\/standard-library\/reference\/([^"]+)"/)?.[1]
    || urlPath.replace(/_index\.md$/, '').replace(/(?:\.ms)?\.md$/, '/');
}

test('reference routes normalize Windows filenames without changing source paths', () => {
  assert.equal(referenceRoute('concurrency\\promise.ms.md', ''), 'concurrency/promise/');
  assert.equal(referenceRoute('concurrency/promise.ms.md', ''), 'concurrency/promise/');
  assert.equal(referenceRoute('concurrency\\_index.md', 'url = "/standard-library/reference/tree/concurrency/"'), 'tree/concurrency/');
  assert.equal(referenceRoute('crypto.ms.md', ''), 'crypto/');
  assert.equal(referenceRoute('_index.md', ''), '');
});

function referencePages() {
  const source = path.join(root, '.artifacts/docs/documentation/standard-library/reference');
  return fs.readdirSync(source, { recursive: true }).filter(file => file.endsWith('.md')).map(file => {
    const markdown = fs.readFileSync(path.join(source, file), 'utf8');
    const route = referenceRoute(file, markdown);
    const aliases = [...markdown.matchAll(/aliases = \["([^"\n]+)"\]/g)].map(match => match[1]);
    return { file, markdown, route, aliases };
  });
}

test('published API routes mirror source directories and preserve old routes', () => {
  const output = path.join(book, 'standard-library/reference');
  const pages = referencePages();
  const expected = pages.flatMap(page => [path.join(page.route, 'index.html'), ...page.aliases.map(alias => path.join(alias.replace('/standard-library/reference/', ''), 'index.html'))]).sort();
  const actual = fs.readdirSync(output, { recursive: true }).filter(file => file.endsWith('index.html')).sort();
  assert.deepEqual(actual, expected, 'Remove obsolete pages and preserve compatibility redirects');
  for (const page of pages) {
    for (const alias of page.aliases) {
      const html = fs.readFileSync(path.join(book, alias, 'index.html'), 'utf8');
      assert.ok(html.includes(`/manuscript/standard-library/reference/${page.route}`));
      let destination;
      const script = html.match(/<script[^>]*>([\s\S]*?)<\/script>/)?.[1];
      assert.ok(script, 'Alias must preserve a method fragment');
      vm.runInNewContext(script, { location: { search: '?from=old', hash: '#promisepromisemethodstwait', replace: value => { destination = value; } } });
      const canonicalTag = [...html.matchAll(/<link\b[^>]*>/g)].map(match => match[0]).find(tag => attribute(tag, 'rel') === 'canonical');
      const canonical = attribute(canonicalTag, 'href');
      assert.equal(new URL(canonical).pathname, `/manuscript/standard-library/reference/${page.route}`);
      assert.equal(destination, `${canonical}?from=old#promisepromisemethodstwait`);

    }
  }
  const promise = fs.readFileSync(path.join(output, 'concurrency/promise/index.html'), 'utf8');
  assert.ok(promise.includes('concurrency'));
  assert.ok(promise.includes('promise.ms'));
});

test('rendered API signatures match source pages without synthetic contracts', () => {
  const entities = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", '#34': '"', '#39': "'" };
  for (const { file, markdown, route } of referencePages()) {
    const expected = [...markdown.matchAll(/```manuscript\n([\s\S]*?)```/g)].map(match => match[1].trimEnd());
    const html = fs.readFileSync(path.join(book, 'standard-library/reference', route, 'index.html'), 'utf8');
    const actual = [...html.matchAll(/<pre\b[^>]*><code\b[^>]*>([\s\S]*?)<\/code><\/pre>/g)]
      .map(match => match[1].replace(/&(amp|lt|gt|quot|apos|#34|#39);/g, (_, entity) => entities[entity]).trimEnd());
    assert.deepEqual(actual, expected, `Rebuild the website: ${file} has stale API signatures`);
    assert.ok(!html.includes('$methods') && !html.includes('SourceMethods'));
  }
});

test('legacy method fragments remain beside the public method headings', () => {
  const page = fs.readFileSync(path.join(book, 'standard-library/reference/concurrency/promise/index.html'), 'utf8');
  for (const [legacy, current] of [['promisepromisemethodstwait', 'promisewait'], ['cancelcancelmethodscancel', 'cancelcancel'], ['signalsignalmethodscancelled', 'signalcancelled']]) {
    assert.ok(new RegExp(`<span id=["']?${legacy}["']?[^>]*></span>\\s*<h3 id=["']?${current}`).test(page), `${legacy} must target ${current}`);
  }
});

test('Promise and stream guides teach separate topics', () => {
  const read = topic => fs.readFileSync(path.join(book, 'core-language/concurrency', topic, 'index.html'), 'utf8');
  const promises = read('promises');
  const streams = read('streams');
  assert.ok(!promises.includes('ReadStream') && !promises.includes('pipe[Update]'));
  for (const text of ['PromiseOptions', 'wait_all', 'Cancellation']) assert.ok(promises.includes(text));
  for (const text of ['ReadStream', 'Transform', 'Pipelines', 'Pipes', 'defers the read']) assert.ok(streams.includes(text));
  assert.ok(promises.includes('/manuscript/core-language/concurrency/streams/'));
  assert.ok(streams.includes('/manuscript/core-language/concurrency/promises/'));
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

test('documentation screenshots resolve, carry alt text, and switch with the theme', () => {
  const prefix = '/manuscript/';
  const failures = [];
  let figures = 0;
  function visit(directory) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const file = path.join(directory, entry.name);
      if (entry.isDirectory()) visit(file);
      else if (entry.name.endsWith('.html')) {
        const text = fs.readFileSync(file, 'utf8');
        for (const figure of text.matchAll(/<figure\b[^>]*docs-shot[^>]*>([\s\S]*?)<\/figure>/g)) {
          figures += 1;
          const images = [...figure[1].matchAll(/<img\b[^>]*>/g)].map(match => match[0]);
          const where = path.relative(book, file);
          if (!images.length) failures.push(`${where}: figure has no image`);
          for (const image of images) {
            const src = attribute(image, 'src');
            if (!attribute(image, 'alt')) failures.push(`${where}: ${src} has no alt text`);
            const target = path.join(book, decodeURIComponent((src || '').replace(prefix, '')));
            if (!src || !fs.existsSync(target)) failures.push(`${where}: ${src} is missing from the book`);
          }
        }
      }
    }
  }
  visit(book);
  assert.deepEqual(failures, []);
  assert.ok(figures > 0, 'Show at least one screenshot');
});

test('previous and next links follow the rendered sidebar reading order', () => {
  const home = fs.readFileSync(path.join(book, 'index.html'), 'utf8');
  const canonical = [...home.matchAll(/<link\b[^>]*>/g)]
    .map(match => match[0]).find(tag => attribute(tag, 'rel') === 'canonical');
  const prefix = new URL(attribute(canonical, 'href')).pathname;
  const start = fs.readFileSync(path.join(book, 'learn/index.html'), 'utf8');
  const nav = start.match(/<nav\b[^>]*aria-label=(?:"Documentation"|'Documentation'|Documentation)[^>]*>[\s\S]*?<\/nav>/)[0];
  const groups = [...nav.matchAll(/<div\b[^>]*class=(?:"nav-group"|'nav-group'|nav-group)[^>]*>([\s\S]*?)<\/div>/g)];
  const routes = groups.flatMap(group => [...group[1].matchAll(/<a\b[^>]*>/g)]
    .map(match => attribute(match[0], 'href')));
  assert.deepEqual(routes.slice(0, 6), [
    'learn/', 'learn/getting-started/', 'learn/testing/',
    'learn/why-manuscript/', 'guide/', 'guide/values-and-functions/',
  ].map(route => prefix + route), 'Teach running, reading, and the guide before task recipes');
  assert.ok(routes.indexOf(prefix + 'guide/cleaning-up/') < routes.indexOf(prefix + 'cookbook/'),
    'The guide comes before task recipes');
  assert.deepEqual(routes.filter(route => route.startsWith(prefix + 'developer-tooling/')).slice(0, 3),
    ['developer-tooling/', 'developer-tooling/how-it-works/', 'developer-tooling/implementation/'].map(route => prefix + route),
    'Teach building and sharing before the tooling command reference');
  assert.equal(new Set(routes).size, routes.length, 'Each page belongs to one sidebar position');
  const retired = fs.readFileSync(path.join(book, 'learn/best-practices/index.html'), 'utf8');
  assert.ok(retired.includes(prefix + 'cookbook/'), 'Retired advice page redirects to runnable recipes');

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


test('the landing page offers a trial while documentation keeps its reading navigation', () => {
  const home = fs.readFileSync(path.join(book, 'index.html'), 'utf8');
  assert.equal((home.match(/<h1\b/g) || []).length, 1, 'Use one clear landing-page headline');
  assert.ok(!/<aside\b[^>]*aria-label=(?:"Documentation navigation"|'Documentation navigation')/.test(home),
    'The landing page should not look like a documentation chapter');
  const primary = [...home.matchAll(/<a\b[^>]*>/g)].map(match => match[0])
    .find(tag => (attribute(tag, 'class') || '').split(' ').includes('home-button-primary'));
  assert.ok(primary, 'Offer a primary trial action');
  assert.ok(attribute(primary, 'href').endsWith('/learn/getting-started/'), 'Start the trial with a runnable guide');
  assert.ok(home.includes('ms run server.ms'), 'Show how to run the displayed program');
  const docs = fs.readFileSync(path.join(book, 'learn/index.html'), 'utf8');
  assert.ok(docs.includes('Documentation navigation'), 'Readers need a documentation sidebar');
});


test('landing and documentation pages share one favicon and a loadable brand mark', () => {
  const home = fs.readFileSync(path.join(book, 'index.html'), 'utf8');
  const canonical = [...home.matchAll(/<link\b[^>]*>/g)].map(match => match[0])
    .find(tag => attribute(tag, 'rel') === 'canonical');
  const prefix = new URL(attribute(canonical, 'href')).pathname;
  const icons = [];
  for (const route of ['index.html', 'learn/index.html']) {
    const html = fs.readFileSync(path.join(book, route), 'utf8');
    const favicons = [...html.matchAll(/<link\b[^>]*>/g)].map(match => match[0])
      .filter(tag => attribute(tag, 'rel') === 'icon');
    assert.equal(favicons.length, 1, `${route}: avoid competing theme and project favicons`);
    icons.push(attribute(favicons[0], 'href'));
    assert.equal(attribute(favicons[0], 'type'), 'image/svg+xml', 'Keep the favicon scalable');
    const brand = [...html.matchAll(/<img\b[^>]*>/g)].map(match => match[0])
      .find(tag => (attribute(tag, 'class') || '').split(' ').includes('brand-mark'));
    assert.ok(brand, `${route}: include the brand mark`);
    assert.equal(attribute(brand, 'src'), icons.at(-1), 'Header and favicon use the same vector mark');
    for (const url of [icons.at(-1), attribute(brand, 'src')]) {
      assert.ok(url.startsWith(prefix), `${route}: branding must respect the site prefix`);
      assert.ok(fs.statSync(path.join(book, url.slice(prefix.length))).size > 0, `${route}: branding asset missing`);
    }
  }
  assert.equal(icons[0], icons[1], 'Use a consistent favicon across the site');
  const manifest = JSON.parse(fs.readFileSync(path.join(book, 'manifest.json'), 'utf8'));
  assert.equal(manifest.start_url, prefix);
  assert.equal(manifest.scope, prefix);
  assert.deepEqual(manifest.icons, [{ src: icons[0], sizes: 'any', type: 'image/svg+xml', purpose: 'any' }]);
  const svg = fs.readFileSync(path.join(book, icons[0].slice(prefix.length)), 'utf8');
  assert.match(svg, /viewBox="0 0 32 32"/);
  assert.ok(!/<(?:image|text|script)\b/.test(svg), 'Brand mark stays self-contained vector geometry');
});
