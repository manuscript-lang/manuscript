// Markdown subset -> HTML converter. Implements the algorithm in TASK.md.
import fs from 'node:fs';

// Sentinel for a two-space hard break inside paragraph text (input is ASCII, so it cannot clash).
const SENT = '';

function esc(s: string): string {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function indentOf(line: string): number {
  let i = 0;
  while (i < line.length && line[i] === ' ') i++;
  return i;
}

function isBlank(line: string): boolean {
  return /^ *$/.test(line);
}

function runLen(s: string, ch: string, from = 0): number {
  let i = from;
  while (i < s.length && s[i] === ch) i++;
  return i - from;
}

function trimSp(s: string): string {
  return s.replace(/^ +/, '').replace(/ +$/, '');
}

// ---------- line classifiers (rules 1-4 tested on a single line) ----------

interface Fence { ch: string; len: number; indent: number; info: string }

function fenceStart(line: string): Fence | null {
  const ind = indentOf(line);
  if (ind > 3) return null;
  const rest = line.slice(ind);
  const ch = rest[0];
  if (ch !== '`' && ch !== '~') return null;
  const n = runLen(rest, ch);
  if (n < 3) return null;
  const info = trimSp(rest.slice(n));
  if (ch === '`' && info.includes('`')) return null;
  return { ch, len: n, indent: ind, info };
}

function isClosingFence(line: string, f: Fence): boolean {
  const ind = indentOf(line);
  if (ind > 3) return false;
  const rest = line.slice(ind);
  if (rest[0] !== f.ch) return false;
  const n = runLen(rest, f.ch);
  return n >= f.len && isBlank(rest.slice(n));
}

interface Atx { level: number; content: string }

function atxHeading(line: string): Atx | null {
  const ind = indentOf(line);
  if (ind > 3) return null;
  const rest = line.slice(ind);
  const m = /^(#{1,6})( |$)/.exec(rest);
  if (!m) return null;
  const level = m[1].length;
  let c = trimSp(rest.slice(level));
  const r = /#+$/.exec(c);
  if (r && (r.index === 0 || c[r.index - 1] === ' ')) c = trimSp(c.slice(0, r.index));
  return { level, content: c };
}

function isHr(line: string): boolean {
  if (indentOf(line) > 3) return false;
  return /^([-*_])\1{2,}$/.test(line.replace(/ /g, ''));
}

function quoteStart(line: string): boolean {
  const ind = indentOf(line);
  return ind <= 3 && line[ind] === '>';
}

interface Marker {
  ordered: boolean;
  bullet: string | null;
  delim: string | null;
  num: number;
  W: number;
  empty: boolean;
}

function listMarker(line: string): Marker | null {
  const ind = indentOf(line);
  if (ind > 3) return null;
  const rest = line.slice(ind);
  let mlen: number;
  let ordered = false;
  let bullet: string | null = null;
  let delim: string | null = null;
  let num = 0;
  if (rest[0] === '-' || rest[0] === '*' || rest[0] === '+') {
    mlen = 1;
    bullet = rest[0];
  } else {
    const m = /^(\d{1,9})([.)])/.exec(rest);
    if (!m) return null;
    mlen = m[0].length;
    ordered = true;
    num = parseInt(m[1], 10);
    delim = m[2];
  }
  const M = ind + mlen;
  const after = line.slice(M);
  if (after.length > 0 && after[0] !== ' ') return null;
  const empty = isBlank(after);
  const spaces = indentOf(after);
  let W: number;
  if (empty || spaces >= 5) W = M + 1;
  else W = M + spaces;
  return { ordered, bullet, delim, num, W, empty };
}

// ---------- tables ----------

function splitRow(line: string): string[] {
  let s = trimSp(line);
  if (s[0] === '|') s = s.slice(1);
  if (s.length > 0 && s[s.length - 1] === '|' && s[s.length - 2] !== '\\') s = s.slice(0, -1);
  const cells: string[] = [];
  let cur = '';
  for (let k = 0; k < s.length; k++) {
    if (s[k] === '|' && s[k - 1] !== '\\') {
      cells.push(cur);
      cur = '';
    } else {
      cur += s[k];
    }
  }
  cells.push(cur);
  return cells.map(trimSp);
}

function isDelimRow(line: string): boolean {
  if (!line.includes('|')) return false;
  return splitRow(line).every((c) => /^:?-+:?$/.test(c));
}

function alignOf(c: string): string | null {
  const l = c[0] === ':';
  const r = c[c.length - 1] === ':';
  if (l && r) return 'center';
  if (l) return 'left';
  if (r) return 'right';
  return null;
}

// ---------- block parsing ----------

interface Block {
  type: string;
  blankBefore?: boolean;
  [key: string]: any;
}

function stopsRow(l: string): boolean {
  return isBlank(l) || fenceStart(l) !== null || atxHeading(l) !== null || isHr(l) || quoteStart(l);
}

function interruptsPara(l: string): boolean {
  const m = listMarker(l);
  return m !== null && !m.empty && (!m.ordered || m.num === 1);
}

function paragraphText(lines: string[]): string {
  let s = '';
  for (let k = 0; k < lines.length; k++) {
    let l = lines[k].replace(/^ +/, '');
    const last = k === lines.length - 1;
    if (last) {
      s += l.replace(/ +$/, '');
    } else if (/ {2}$/.test(l)) {
      s += l.replace(/ +$/, '') + SENT;
    } else {
      s += l.replace(/ +$/, '') + '\n';
    }
  }
  return s;
}

function parseBlocks(lines: string[]): Block[] {
  const blocks: Block[] = [];
  let i = 0;
  let blank = false;
  while (i < lines.length) {
    if (isBlank(lines[i])) {
      blank = true;
      i++;
      continue;
    }
    const r = parseOne(lines, i);
    r.block.blankBefore = blank && blocks.length > 0;
    blank = false;
    blocks.push(r.block);
    i = r.next;
  }
  return blocks;
}

function parseOne(lines: string[], i: number): { block: Block; next: number } {
  const line = lines[i];
  const n = lines.length;
  const ind = indentOf(line);

  // 1. fenced code
  const f = fenceStart(line);
  if (f) {
    const content: string[] = [];
    let j = i + 1;
    let closed = false;
    while (j < n) {
      if (isClosingFence(lines[j], f)) {
        closed = true;
        break;
      }
      content.push(lines[j].slice(Math.min(f.indent, indentOf(lines[j]))));
      j++;
    }
    return {
      block: { type: 'code', lang: f.info ? f.info.split(' ')[0] : null, lines: content },
      next: closed ? j + 1 : n,
    };
  }

  // 2. ATX heading
  const h = atxHeading(line);
  if (h) return { block: { type: 'heading', level: h.level, text: h.content }, next: i + 1 };

  // 3. thematic break
  if (isHr(line)) return { block: { type: 'hr' }, next: i + 1 };

  // 4. block quote
  if (quoteStart(line)) {
    const inner: string[] = [];
    let j = i;
    while (j < n && quoteStart(lines[j])) {
      const l = lines[j];
      let r = l.slice(indentOf(l) + 1);
      if (r[0] === ' ') r = r.slice(1);
      inner.push(r);
      j++;
    }
    return { block: { type: 'quote', children: parseBlocks(inner) }, next: j };
  }

  // 5. list
  if (listMarker(line)) return parseList(lines, i);

  // 6. indented code
  if (ind >= 4) {
    let j = i;
    let last = i;
    while (j < n && (isBlank(lines[j]) || indentOf(lines[j]) >= 4)) {
      if (!isBlank(lines[j])) last = j;
      j++;
    }
    const content = lines.slice(i, last + 1).map((l) => l.slice(Math.min(4, indentOf(l))));
    return { block: { type: 'code', lang: null, lines: content }, next: last + 1 };
  }

  // 7. table
  if (i + 1 < n && line.includes('|') && isDelimRow(lines[i + 1])) {
    const head = splitRow(line);
    const delim = splitRow(lines[i + 1]);
    if (head.length === delim.length) {
      const rows: string[][] = [];
      let j = i + 2;
      while (j < n && !stopsRow(lines[j])) {
        rows.push(splitRow(lines[j]));
        j++;
      }
      return {
        block: { type: 'table', aligns: delim.map(alignOf), head, rows },
        next: j,
      };
    }
  }

  // 8. paragraph
  let j = i + 1;
  while (
    j < n &&
    !(
      isBlank(lines[j]) ||
      fenceStart(lines[j]) ||
      atxHeading(lines[j]) ||
      isHr(lines[j]) ||
      quoteStart(lines[j]) ||
      interruptsPara(lines[j])
    )
  ) {
    j++;
  }
  return { block: { type: 'para', text: paragraphText(lines.slice(i, j)) }, next: j };
}

function parseList(lines: string[], i: number): { block: Block; next: number } {
  const n = lines.length;
  const first = listMarker(lines[i])!;
  const items: { children: Block[] }[] = [];
  let loose = false;
  let pos = i;
  let end = i;
  for (;;) {
    const m = listMarker(lines[pos])!;
    const W = m.W;
    const content: string[] = [m.empty ? '' : lines[pos].slice(W)];
    end = pos + 1;
    let blanks = 0;
    let j = pos + 1;
    while (j < n) {
      const l = lines[j];
      if (isBlank(l)) {
        blanks++;
        j++;
        continue;
      }
      if (indentOf(l) >= W) {
        for (let k = 0; k < blanks; k++) content.push('');
        blanks = 0;
        content.push(l.slice(W));
        j++;
        end = j;
        continue;
      }
      break;
    }
    items.push({ children: parseBlocks(content) });

    // Look at the next non-blank line for another item of the same list.
    let q = end;
    while (q < n && isBlank(lines[q])) q++;
    const nm = q < n ? listMarker(lines[q]) : null;
    const sameKind =
      nm !== null &&
      !isHr(lines[q]) &&
      nm.ordered === first.ordered &&
      (nm.ordered ? nm.delim === first.delim : nm.bullet === first.bullet);
    if (sameKind) {
      if (q > end) loose = true;
      pos = q;
      continue;
    }
    break;
  }
  for (const it of items) {
    if (it.children.some((b, idx) => idx > 0 && b.blankBefore)) loose = true;
  }
  return {
    block: { type: 'list', ordered: first.ordered, start: first.num, loose, items },
    next: end,
  };
}

// ---------- inline processing ----------

function isWs(c: string | undefined): boolean {
  return c === undefined || c === ' ' || c === '\n' || c === SENT;
}

function isPunct(c: string | undefined): boolean {
  return c !== undefined && /^[!-\/:-@\[-`{-~]$/.test(c);
}

function isNL(c: string | undefined): boolean {
  return c === '\n' || c === SENT;
}

interface Tail { dest: string; title: string | undefined; end: number }

function parseTail(text: string, p: number): Tail | null {
  if (text[p] !== '(') return null;
  const n = text.length;
  let j = p + 1;
  const skipWs = () => {
    while (j < n && (text[j] === ' ' || isNL(text[j]))) j++;
  };
  skipWs();
  let dest = '';
  if (text[j] === '<') {
    let k = j + 1;
    let ok = false;
    while (k < n) {
      const c = text[k];
      if (c === '\\' && k + 1 < n && isPunct(text[k + 1])) {
        dest += text[k + 1];
        k += 2;
        continue;
      }
      if (c === '>') {
        ok = true;
        break;
      }
      if (c === '<' || isNL(c)) break;
      dest += c;
      k++;
    }
    if (!ok) return null;
    j = k + 1;
  } else {
    let depth = 0;
    while (j < n) {
      const c = text[j];
      if (c === '\\' && j + 1 < n && isPunct(text[j + 1])) {
        dest += text[j + 1];
        j += 2;
        continue;
      }
      if (c === ' ' || isNL(c)) break;
      if (c === '(') depth++;
      else if (c === ')') {
        if (depth === 0) break;
        depth--;
      }
      dest += c;
      j++;
    }
    if (depth !== 0) return null;
  }
  let title: string | undefined;
  const j0 = j;
  skipWs();
  if (j > j0 && text[j] === '"') {
    let k = j + 1;
    let t = '';
    let ok = false;
    while (k < n) {
      const c = text[k];
      if (c === '\\' && text[k + 1] === '"') {
        t += '"';
        k += 2;
        continue;
      }
      if (c === '"') {
        ok = true;
        break;
      }
      t += c;
      k++;
    }
    if (!ok) return null;
    title = t;
    j = k + 1;
    skipWs();
  }
  if (text[j] !== ')') return null;
  return { dest, title, end: j + 1 };
}

// Emphasis resolution over a node list (mutates the list).
function resolveEmph(nodes: any[]): void {
  let ci = 0;
  while (ci < nodes.length) {
    const c = nodes[ci];
    if (c.t !== 'delim' || !c.canClose) {
      ci++;
      continue;
    }
    let oi = -1;
    for (let k = ci - 1; k >= 0; k--) {
      const o = nodes[k];
      if (o.t !== 'delim' || o.ch !== c.ch || !o.canOpen || o.n === 0) continue;
      if ((o.canClose || c.canOpen) && (o.orig + c.orig) % 3 === 0 && !(o.orig % 3 === 0 && c.orig % 3 === 0)) continue;
      oi = k;
      break;
    }
    if (oi < 0) {
      ci++;
      continue;
    }
    const o = nodes[oi];
    const use = o.n >= 2 && c.n >= 2 ? 2 : 1;
    const inner = nodes.slice(oi + 1, ci);
    nodes.splice(oi + 1, ci - oi - 1, { t: use === 2 ? 'strong' : 'em', children: inner });
    ci = oi + 2;
    o.n -= use;
    c.n -= use;
    if (o.n === 0) {
      nodes.splice(oi, 1);
      ci--;
    }
    if (c.n === 0) nodes.splice(ci, 1);
  }
}

function inline(text: string): string {
  return renderInline(scanInline(text));
}

function scanInline(text: string): any[] {
  const nodes: any[] = [];
  const n = text.length;
  const lit = (s: string) => {
    const last = nodes[nodes.length - 1];
    if (last && last.t === 'text') last.s += s;
    else nodes.push({ t: 'text', s });
  };
  let i = 0;
  while (i < n) {
    const c = text[i];
    if (c === '\\') {
      const d = text[i + 1];
      if (d === '\n') {
        nodes.push({ t: 'br' });
        i += 2;
      } else if (d !== undefined && isPunct(d)) {
        lit(d);
        i += 2;
      } else {
        lit('\\');
        i++;
      }
      continue;
    }
    if (c === SENT) {
      nodes.push({ t: 'br' });
      i++;
      continue;
    }
    if (c === '\n') {
      nodes.push({ t: 'soft' });
      i++;
      continue;
    }
    if (c === '`') {
      const k = runLen(text, '`', i);
      let found = -1;
      let p = i + k;
      while (p < n) {
        const q = text.indexOf('`', p);
        if (q < 0) break;
        const m = runLen(text, '`', q);
        if (m === k) {
          found = q;
          break;
        }
        p = q + m;
      }
      if (found < 0) {
        lit('`'.repeat(k));
        i += k;
        continue;
      }
      let content = text.slice(i + k, found).replace(/[\n]/g, ' ');
      if (content.length >= 2 && content[0] === ' ' && content[content.length - 1] === ' ' && !/^ *$/.test(content)) {
        content = content.slice(1, -1);
      }
      nodes.push({ t: 'code', s: content });
      i = found + k;
      continue;
    }
    if (c === '*' || c === '_') {
      const k = runLen(text, c, i);
      const prev = i > 0 ? text[i - 1] : undefined;
      const next = i + k < n ? text[i + k] : undefined;
      const pw = isWs(prev);
      const nw = isWs(next);
      const pp = isPunct(prev);
      const np = isPunct(next);
      const left = !nw && (!np || pw || pp);
      const right = !pw && (!pp || nw || np);
      let canOpen: boolean;
      let canClose: boolean;
      if (c === '*') {
        canOpen = left;
        canClose = right;
      } else {
        canOpen = left && (!right || pp);
        canClose = right && (!left || np);
      }
      nodes.push({ t: 'delim', ch: c, n: k, orig: k, canOpen, canClose });
      i += k;
      continue;
    }
    if (c === '!' && text[i + 1] === '[') {
      nodes.push({ t: 'opener', image: true, active: true });
      i += 2;
      continue;
    }
    if (c === '[') {
      nodes.push({ t: 'opener', image: false, active: true });
      i++;
      continue;
    }
    if (c === ']') {
      let oi = -1;
      for (let k = nodes.length - 1; k >= 0; k--) {
        if (nodes[k].t === 'opener') {
          oi = k;
          break;
        }
      }
      if (oi < 0) {
        lit(']');
        i++;
        continue;
      }
      const op = nodes[oi];
      if (!op.image && !op.active) {
        nodes[oi] = { t: 'text', s: '[' };
        lit(']');
        i++;
        continue;
      }
      const tail = parseTail(text, i + 1);
      if (!tail) {
        nodes[oi] = { t: 'text', s: op.image ? '![' : '[' };
        lit(']');
        i++;
        continue;
      }
      const removed = nodes.splice(oi);
      const children = removed.slice(1);
      resolveEmph(children);
      nodes.push({ t: 'link', image: op.image, dest: tail.dest, title: tail.title, children });
      if (!op.image) {
        for (const nd of nodes) if (nd.t === 'opener' && !nd.image) nd.active = false;
      }
      i = tail.end;
      continue;
    }
    lit(c);
    i++;
  }
  // Unmatched openers become literal text.
  for (let k = 0; k < nodes.length; k++) {
    if (nodes[k].t === 'opener') nodes[k] = { t: 'text', s: nodes[k].image ? '![' : '[' };
  }
  resolveEmph(nodes);
  return nodes;
}

function plain(nodes: any[]): string {
  let s = '';
  for (const nd of nodes) {
    switch (nd.t) {
      case 'text':
      case 'code':
        s += nd.s;
        break;
      case 'soft':
      case 'br':
        s += ' ';
        break;
      case 'delim':
        s += nd.ch.repeat(nd.n);
        break;
      case 'em':
      case 'strong':
      case 'link':
        s += plain(nd.children);
        break;
    }
  }
  return s;
}

function renderInline(nodes: any[]): string {
  let out = '';
  for (const nd of nodes) {
    switch (nd.t) {
      case 'text':
        out += esc(nd.s);
        break;
      case 'soft':
        out += '\n';
        break;
      case 'br':
        out += '<br />\n';
        break;
      case 'code':
        out += `<code>${esc(nd.s)}</code>`;
        break;
      case 'delim':
        out += esc(nd.ch.repeat(nd.n));
        break;
      case 'em':
        out += `<em>${renderInline(nd.children)}</em>`;
        break;
      case 'strong':
        out += `<strong>${renderInline(nd.children)}</strong>`;
        break;
      case 'link':
        if (nd.image) {
          out += `<img src="${esc(nd.dest)}" alt="${esc(plain(nd.children))}"${nd.title !== undefined ? ` title="${esc(nd.title)}"` : ''} />`;
        } else {
          out += `<a href="${esc(nd.dest)}"${nd.title !== undefined ? ` title="${esc(nd.title)}"` : ''}>${renderInline(nd.children)}</a>`;
        }
        break;
    }
  }
  return out;
}

// ---------- rendering ----------

function renderBlocks(blocks: Block[]): string {
  return blocks.map(renderBlock).join('');
}

function renderBlock(b: Block): string {
  switch (b.type) {
    case 'para':
      return `<p>${inline(b.text)}</p>\n`;
    case 'heading':
      return `<h${b.level}>${inline(b.text)}</h${b.level}>\n`;
    case 'hr':
      return '<hr />\n';
    case 'quote':
      return `<blockquote>\n${renderBlocks(b.children)}</blockquote>\n`;
    case 'code': {
      const cls = b.lang !== null ? ` class="language-${esc(b.lang)}"` : '';
      return `<pre><code${cls}>` + b.lines.map((l: string) => esc(l) + '\n').join('') + '</code></pre>\n';
    }
    case 'list':
      return renderList(b);
    case 'table':
      return renderTable(b);
  }
  return '';
}

function renderList(b: Block): string {
  let out = b.ordered ? (b.start === 1 ? '<ol>\n' : `<ol start="${b.start}">\n`) : '<ul>\n';
  for (const it of b.items) {
    let body = '';
    for (const c of it.children) {
      if (!b.loose && c.type === 'para') {
        body += inline(c.text);
        continue;
      }
      if (body === '' || !body.endsWith('\n')) body += '\n';
      body += renderBlock(c);
    }
    out += `<li>${body}</li>\n`;
  }
  out += b.ordered ? '</ol>\n' : '</ul>\n';
  return out;
}

function renderTable(b: Block): string {
  const cell = (tag: string, idx: number, text: string) => {
    const a = b.aligns[idx];
    return `<${tag}${a ? ` align="${a}"` : ''}>${inline(text)}</${tag}>\n`;
  };
  let out = '<table>\n<thead>\n<tr>\n';
  b.head.forEach((c: string, k: number) => {
    out += cell('th', k, c);
  });
  out += '</tr>\n</thead>\n';
  if (b.rows.length > 0) {
    out += '<tbody>\n';
    for (const r of b.rows) {
      out += '<tr>\n';
      for (let k = 0; k < b.head.length; k++) out += cell('td', k, r[k] ?? '');
      out += '</tr>\n';
    }
    out += '</tbody>\n';
  }
  return out + '</table>\n';
}

// ---------- main ----------

const data = fs.readFileSync(0, 'utf8');
if (data.length > 0) {
  const lines = data.split('\n');
  if (data.endsWith('\n')) lines.pop();
  process.stdout.write(renderBlocks(parseBlocks(lines)));
}
