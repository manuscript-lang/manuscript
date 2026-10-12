const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '../..');
const book = process.env.MANUSCRIPT_BOOK_DIR || path.join(root, 'docs');

test('published API downloads match the current generated reference', () => {
  for (const file of ['stdlib.json', 'stdlib.md']) {
    assert.equal(
      fs.readFileSync(path.join(book, file), 'utf8'),
      fs.readFileSync(path.join(root, 'static', file), 'utf8'),
      `Rebuild the website: ${file} is stale`,
    );
  }
});

test('published API routes contain exactly the current modules', () => {
  const source = path.join(root, 'design/standard-library/reference');
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
  const source = path.join(root, 'design/standard-library/reference');
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
