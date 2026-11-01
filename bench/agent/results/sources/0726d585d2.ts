// Read stdin, write stdout. See TASK.md.
// Backtracking regular-expression engine (no regex library) and command driver.

import { readFileSync } from 'node:fs';
import { Worker, isMainThread, parentPort, workerData } from 'node:worker_threads';

class RegexError extends Error {}

function fail(msg: string): never {
  throw new RegexError(msg);
}

const INF = Number.POSITIVE_INFINITY;

interface Flags {
  i: boolean;
  m: boolean;
  s: boolean;
}

type Seq = Node[];
type Alts = Seq[];

interface BackrefNode {
  t: 'backref';
  idx: number;
  ref: number | string;
  icase: boolean;
}

type Node =
  | { t: 'set'; set: Uint8Array }
  | { t: 'assert'; kind: 'bol' | 'eol' | 'wb' | 'nwb' }
  | { t: 'group'; idx: number; alts: Alts }
  | { t: 'look'; neg: boolean; alts: Alts }
  | BackrefNode
  | { t: 'repeat'; min: number; max: number; greedy: boolean; body: Node };

function makeSet(pred: (c: number) => boolean): Uint8Array {
  const s = new Uint8Array(256);
  for (let c = 0; c < 256; c++) if (pred(c)) s[c] = 1;
  return s;
}

function complement(s: Uint8Array): Uint8Array {
  return makeSet((c) => s[c] === 0);
}

function isDigitCode(c: number): boolean {
  return c >= 48 && c <= 57;
}

function isAlnum(c: number): boolean {
  return isDigitCode(c) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
}

function isWordCode(c: number): boolean {
  return isAlnum(c) || c === 95;
}

function isNameStart(c: number): boolean {
  return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c === 95;
}

function hexVal(c: number): number {
  if (c >= 48 && c <= 57) return c - 48;
  if (c >= 65 && c <= 70) return c - 55;
  if (c >= 97 && c <= 102) return c - 87;
  return -1;
}

const DIGIT = makeSet(isDigitCode);
const WORD = makeSet(isWordCode);
const SPACE = makeSet((c) => c === 32 || (c >= 9 && c <= 13));
const NDIGIT = complement(DIGIT);
const NWORD = complement(WORD);
const NSPACE = complement(SPACE);
const ALL = makeSet(() => true);
const DOT = makeSet((c) => c !== 10);

// Make a set case-insensitive for ASCII letters.
function foldCase(set: Uint8Array): void {
  for (let c = 65; c <= 90; c++) {
    if (set[c] || set[c + 32]) {
      set[c] = 1;
      set[c + 32] = 1;
    }
  }
}

function lowerAscii(c: number): number {
  return c >= 65 && c <= 90 ? c + 32 : c;
}

function quantifiable(n: Node): boolean {
  return n.t === 'set' || n.t === 'group' || n.t === 'backref';
}

class Parser {
  src: string;
  flags: Flags;
  pos: number;
  ngroups: number;
  names: Map<string, number>;
  groupNames: (string | undefined)[];
  backrefs: BackrefNode[];
  depth: number;

  constructor(src: string, flags: Flags) {
    this.src = src;
    this.flags = flags;
    this.pos = 0;
    this.ngroups = 0;
    this.names = new Map();
    this.groupNames = [];
    this.backrefs = [];
    this.depth = 0;
  }

  parse(): Alts {
    const alts = this.parseAlts();
    for (const b of this.backrefs) {
      if (typeof b.ref === 'number') {
        if (b.ref > this.ngroups) fail('bad backreference');
        b.idx = b.ref;
      } else {
        const idx = this.names.get(b.ref);
        if (idx === undefined) fail('bad backreference');
        b.idx = idx;
      }
    }
    return alts;
  }

  parseAlts(): Alts {
    const alts: Alts = [this.parseSeq()];
    while (this.pos < this.src.length && this.src[this.pos] === '|') {
      this.pos++;
      alts.push(this.parseSeq());
    }
    return alts;
  }

  parseSeq(): Seq {
    const s = this.src;
    const items: Node[] = [];
    while (this.pos < s.length) {
      const c = s[this.pos];
      if (c === '|') break;
      if (c === ')') {
        if (this.depth > 0) break;
        fail('unmatched )');
      }
      if (c === '*' || c === '+' || c === '?') fail('nothing to repeat');
      // A quantifier directly after a quantifier (items non-empty here only
      // when the previous item was quantified).
      if (c === '{' && items.length > 0 && this.quantEnd(this.pos) >= 0) {
        fail('nothing to repeat');
      }
      const atom = this.parseAtom();
      items.push(this.parsePostfix(atom));
    }
    return items;
  }

  // If a valid quantifier shape starts at p (src[p] === '{'), return the index after it; else -1.
  quantEnd(p: number): number {
    const s = this.src;
    let i = p + 1;
    const d0 = i;
    while (i < s.length && isDigitCode(s.charCodeAt(i))) i++;
    if (i === d0) return -1;
    if (s[i] === '}') return i + 1;
    if (s[i] !== ',') return -1;
    i++;
    while (i < s.length && isDigitCode(s.charCodeAt(i))) i++;
    if (s[i] === '}') return i + 1;
    return -1;
  }

  parsePostfix(atom: Node): Node {
    const s = this.src;
    const c = s[this.pos];
    let min = 0;
    let max = INF;
    let end: number;
    if (c === '*') {
      end = this.pos + 1;
    } else if (c === '+') {
      min = 1;
      end = this.pos + 1;
    } else if (c === '?') {
      max = 1;
      end = this.pos + 1;
    } else if (c === '{' && (end = this.quantEnd(this.pos)) >= 0) {
      // handled below after checks
    } else {
      return atom;
    }
    if (!quantifiable(atom)) fail('nothing to repeat');
    if (c === '{') {
      const body = s.slice(this.pos + 1, end - 1);
      const comma = body.indexOf(',');
      const minS = comma < 0 ? body : body.slice(0, comma);
      const maxS = comma < 0 ? minS : body.slice(comma + 1);
      min = numVal(minS);
      max = comma < 0 ? min : maxS === '' ? INF : numVal(maxS);
      if (min > 1000 || (max !== INF && max > 1000) || min > max) fail('bad repeat');
    }
    this.pos = end;
    let greedy = true;
    if (s[this.pos] === '?') {
      greedy = false;
      this.pos++;
    }
    return { t: 'repeat', min, max, greedy, body: atom };
  }

  parseAtom(): Node {
    const s = this.src;
    const c = s[this.pos];
    switch (c) {
      case '.':
        this.pos++;
        return { t: 'set', set: this.flags.s ? ALL : DOT };
      case '[':
        this.pos++;
        return this.parseClass();
      case '(':
        return this.parseGroup();
      case '^':
        this.pos++;
        return { t: 'assert', kind: 'bol' };
      case '$':
        this.pos++;
        return { t: 'assert', kind: 'eol' };
      case '\\':
        return this.parseEscape();
      default:
        this.pos++;
        return this.literal(s.charCodeAt(this.pos - 1));
    }
  }

  literal(code: number): Node {
    const set = new Uint8Array(256);
    set[code] = 1;
    if (this.flags.i) foldCase(set);
    return { t: 'set', set };
  }

  // Reads a group/backreference name starting at p, terminated by '>'.
  readName(p: number): { name: string; end: number } | null {
    const s = this.src;
    if (p >= s.length || !isNameStart(s.charCodeAt(p))) return null;
    let q = p + 1;
    while (q < s.length && isWordCode(s.charCodeAt(q))) q++;
    if (s[q] !== '>') return null;
    return { name: s.slice(p, q), end: q + 1 };
  }

  parseGroup(): Node {
    const s = this.src;
    this.pos++; // '('
    let idx = -1;
    let isLook = false;
    let lookNeg = false;
    if (s[this.pos] === '?') {
      const c2 = s[this.pos + 1];
      if (c2 === ':') {
        this.pos += 2;
      } else if (c2 === '=' || c2 === '!') {
        isLook = true;
        lookNeg = c2 === '!';
        this.pos += 2;
      } else if (c2 === '<') {
        const r = this.readName(this.pos + 2);
        if (r === null) fail('bad group');
        if (this.names.has(r.name)) fail('duplicate group name');
        idx = ++this.ngroups;
        this.names.set(r.name, idx);
        this.groupNames[idx] = r.name;
        this.pos = r.end;
      } else {
        fail('bad group');
      }
    } else {
      idx = ++this.ngroups;
    }
    this.depth++;
    const alts = this.parseAlts();
    this.depth--;
    if (s[this.pos] !== ')') fail('unmatched (');
    this.pos++;
    if (isLook) return { t: 'look', neg: lookNeg, alts };
    return { t: 'group', idx, alts };
  }

  readHex(): number {
    const a = hexVal(this.src.charCodeAt(this.pos));
    const b = hexVal(this.src.charCodeAt(this.pos + 1));
    if (a < 0 || b < 0) fail('bad escape');
    this.pos += 2;
    return a * 16 + b;
  }

  mkBackref(ref: number | string): Node {
    const node: BackrefNode = { t: 'backref', idx: -1, ref, icase: this.flags.i };
    this.backrefs.push(node);
    return node;
  }

  // pos is at the backslash.
  parseEscape(): Node {
    const s = this.src;
    this.pos++;
    if (this.pos >= s.length) fail('bad escape');
    const code = s.charCodeAt(this.pos);
    const c = s[this.pos];
    this.pos++;
    switch (c) {
      case 'd': return { t: 'set', set: DIGIT };
      case 'D': return { t: 'set', set: NDIGIT };
      case 'w': return { t: 'set', set: WORD };
      case 'W': return { t: 'set', set: NWORD };
      case 's': return { t: 'set', set: SPACE };
      case 'S': return { t: 'set', set: NSPACE };
      case 'b': return { t: 'assert', kind: 'wb' };
      case 'B': return { t: 'assert', kind: 'nwb' };
      case 'n': return this.literal(10);
      case 't': return this.literal(9);
      case 'r': return this.literal(13);
      case 'x': return this.literal(this.readHex());
      case 'k': {
        if (s[this.pos] !== '<') fail('bad escape');
        const r = this.readName(this.pos + 1);
        if (r === null) fail('bad escape');
        this.pos = r.end;
        return this.mkBackref(r.name);
      }
      default:
        if (code >= 49 && code <= 57) return this.mkBackref(code - 48);
        if (isAlnum(code) || code >= 128) fail('bad escape');
        return this.literal(code);
    }
  }

  // Reads one class element: a byte (v) or a shorthand set (short).
  readClassAtom(): { short: Uint8Array | null; v: number } {
    const s = this.src;
    if (s[this.pos] !== '\\') {
      this.pos++;
      return { short: null, v: s.charCodeAt(this.pos - 1) };
    }
    this.pos++;
    if (this.pos >= s.length) fail('unterminated class');
    const code = s.charCodeAt(this.pos);
    const c = s[this.pos];
    this.pos++;
    switch (c) {
      case 'd': return { short: DIGIT, v: 0 };
      case 'D': return { short: NDIGIT, v: 0 };
      case 'w': return { short: WORD, v: 0 };
      case 'W': return { short: NWORD, v: 0 };
      case 's': return { short: SPACE, v: 0 };
      case 'S': return { short: NSPACE, v: 0 };
      case 'n': return { short: null, v: 10 };
      case 't': return { short: null, v: 9 };
      case 'r': return { short: null, v: 13 };
      case 'x': return { short: null, v: this.readHex() };
      default:
        if (isAlnum(code) || code >= 128) fail('bad escape');
        return { short: null, v: code };
    }
  }

  parseClass(): Node {
    const s = this.src;
    let neg = false;
    if (s[this.pos] === '^') {
      neg = true;
      this.pos++;
    }
    const set = new Uint8Array(256);
    let first = true;
    let afterRange = false;
    for (;;) {
      if (this.pos >= s.length) fail('unterminated class');
      if (s[this.pos] === ']' && !first) {
        this.pos++;
        break;
      }
      first = false;
      const el = this.readClassAtom();
      if (el.short !== null) {
        for (let c = 0; c < 256; c++) if (el.short[c]) set[c] = 1;
        if (s[this.pos] === '-' && this.pos + 1 < s.length && s[this.pos + 1] !== ']') {
          fail('bad range');
        }
        afterRange = false;
        continue;
      }
      if (!afterRange && s[this.pos] === '-' && this.pos + 1 < s.length && s[this.pos + 1] !== ']') {
        this.pos++;
        const end = this.readClassAtom();
        if (end.short !== null || end.v < el.v) fail('bad range');
        for (let c = el.v; c <= end.v; c++) set[c] = 1;
        afterRange = true;
      } else {
        set[el.v] = 1;
        afterRange = false;
      }
    }
    if (this.flags.i) foldCase(set);
    return { t: 'set', set: neg ? complement(set) : set };
  }
}

function numVal(t: string): number {
  let v = 0;
  for (let i = 0; i < t.length; i++) {
    v = v * 10 + (t.charCodeAt(i) - 48);
    if (v > 1e9) v = 1e9;
  }
  return v;
}

interface Compiled {
  alts: Alts;
  ngroups: number;
  groupNames: (string | undefined)[];
  flags: Flags;
}

function compile(pattern: string): Compiled {
  const flags: Flags = { i: false, m: false, s: false };
  let start = 0;
  if (pattern.startsWith('(?')) {
    let j = 2;
    let any = false;
    const f: Flags = { i: false, m: false, s: false };
    while (j < pattern.length && 'ims'.indexOf(pattern[j]) >= 0) {
      const ch = pattern[j];
      if (ch === 'i') f.i = true;
      else if (ch === 'm') f.m = true;
      else f.s = true;
      any = true;
      j++;
    }
    if (any && pattern[j] === ')') {
      flags.i = f.i;
      flags.m = f.m;
      flags.s = f.s;
      start = j + 1;
    }
  }
  const p = new Parser(pattern, flags);
  p.pos = start;
  const alts = p.parse();
  return { alts, ngroups: p.ngroups, groupNames: p.groupNames, flags };
}

interface Result {
  st: number;
  end: number;
  caps: Int32Array;
}

class Matcher {
  s: string;
  n: number;
  flags: Flags;
  alts: Alts;
  caps: Int32Array;

  constructor(c: Compiled, s: string) {
    this.s = s;
    this.n = s.length;
    this.flags = c.flags;
    this.alts = c.alts;
    this.caps = new Int32Array(2 * (c.ngroups + 1));
  }

  matchAlts(alts: Alts, pos: number, k: (p: number) => boolean): boolean {
    for (const seq of alts) {
      if (this.matchSeq(seq, 0, pos, k)) return true;
    }
    return false;
  }

  matchSeq(seq: Seq, i: number, pos: number, k: (p: number) => boolean): boolean {
    if (i === seq.length) return k(pos);
    const node = seq[i];
    if (node.t === 'set') {
      if (pos < this.n && node.set[this.s.charCodeAt(pos)]) {
        return this.matchSeq(seq, i + 1, pos + 1, k);
      }
      return false;
    }
    return this.matchNode(node, pos, (p) => this.matchSeq(seq, i + 1, p, k));
  }

  isWordAt(p: number): boolean {
    return p >= 0 && p < this.n && WORD[this.s.charCodeAt(p)] === 1;
  }

  checkAssert(kind: string, pos: number): boolean {
    switch (kind) {
      case 'bol':
        return pos === 0 || (this.flags.m && this.s.charCodeAt(pos - 1) === 10);
      case 'eol':
        return pos === this.n || (this.flags.m && this.s.charCodeAt(pos) === 10);
      case 'wb':
        return this.isWordAt(pos - 1) !== this.isWordAt(pos);
      default:
        return this.isWordAt(pos - 1) === this.isWordAt(pos);
    }
  }

  matchNode(node: Node, pos: number, k: (p: number) => boolean): boolean {
    switch (node.t) {
      case 'set':
        if (pos < this.n && node.set[this.s.charCodeAt(pos)]) return k(pos + 1);
        return false;
      case 'assert':
        return this.checkAssert(node.kind, pos) ? k(pos) : false;
      case 'group': {
        const idx = node.idx;
        return this.matchAlts(node.alts, pos, (p) => {
          if (idx < 0) return k(p);
          const caps = this.caps;
          const os = caps[2 * idx];
          const oe = caps[2 * idx + 1];
          caps[2 * idx] = pos;
          caps[2 * idx + 1] = p;
          if (k(p)) return true;
          caps[2 * idx] = os;
          caps[2 * idx + 1] = oe;
          return false;
        });
      }
      case 'look': {
        const saved = this.caps.slice();
        const ok = this.matchAlts(node.alts, pos, () => true);
        if (node.neg) {
          this.caps.set(saved);
          if (ok) return false;
          return k(pos);
        }
        if (!ok) {
          this.caps.set(saved);
          return false;
        }
        if (k(pos)) return true;
        this.caps.set(saved);
        return false;
      }
      case 'backref': {
        const st = this.caps[2 * node.idx];
        if (st < 0) return false;
        const len = this.caps[2 * node.idx + 1] - st;
        if (pos + len > this.n) return false;
        for (let j = 0; j < len; j++) {
          const a = this.s.charCodeAt(st + j);
          const b = this.s.charCodeAt(pos + j);
          if (a === b) continue;
          if (node.icase && lowerAscii(a) === lowerAscii(b)) continue;
          return false;
        }
        return k(pos + len);
      }
      case 'repeat': {
        if (node.body.t === 'set') {
          // Fast path: single-byte body, no captures involved.
          const set = node.body.set;
          let cnt = 0;
          while (cnt < node.max && pos + cnt < this.n && set[this.s.charCodeAt(pos + cnt)]) cnt++;
          if (cnt < node.min) return false;
          if (node.greedy) {
            for (let j = cnt; j >= node.min; j--) if (k(pos + j)) return true;
          } else {
            for (let j = node.min; j <= cnt; j++) if (k(pos + j)) return true;
          }
          return false;
        }
        return this.rep(node, 0, pos, k);
      }
    }
  }

  rep(node: { min: number; max: number; greedy: boolean; body: Node }, count: number, pos: number, k: (p: number) => boolean): boolean {
    if (count < node.min) {
      return this.matchNode(node.body, pos, (p) => this.rep(node, count + 1, p, k));
    }
    const more = (): boolean =>
      count < node.max &&
      this.matchNode(node.body, pos, (p) => {
        if (p === pos) return k(p); // empty iteration after min ends the loop
        return this.rep(node, count + 1, p, k);
      });
    if (node.greedy) return more() || k(pos);
    return k(pos) || more();
  }

  // Attempt a match starting exactly at st. Returns true on success (caps set).
  attempt(st: number, full: boolean): boolean {
    this.caps.fill(-1);
    let end = -1;
    const ok = this.matchAlts(this.alts, st, (p) => {
      if (full && p !== this.n) return false;
      end = p;
      return true;
    });
    if (!ok) return false;
    this.caps[0] = st;
    this.caps[1] = end;
    return true;
  }

  searchFrom(from: number, full: boolean): Result | null {
    for (let st = from; st <= this.n; st++) {
      if (full && st !== 0) break;
      if (this.attempt(st, full)) {
        return { st, end: this.caps[1], caps: this.caps.slice() };
      }
    }
    return null;
  }
}

function quoted(s: string): string {
  let out = '"';
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c === 92) out += '\\\\';
    else if (c === 34) out += '\\"';
    else if (c === 10) out += '\\n';
    else if (c === 9) out += '\\t';
    else if (c === 13) out += '\\r';
    else if (c < 0x20 || c > 0x7e) out += '\\x' + c.toString(16).padStart(2, '0');
    else out += s[i];
  }
  return out + '"';
}

function unescapeField(f: string): string | null {
  let out = '';
  for (let i = 0; i < f.length; i++) {
    const c = f[i];
    if (c !== '\\') {
      out += c;
      continue;
    }
    i++;
    if (i >= f.length) return null;
    const e = f[i];
    if (e === 'n') out += '\n';
    else if (e === 't') out += '\t';
    else if (e === '\\') out += '\\';
    else if (e === 'x') {
      const a = hexVal(f.charCodeAt(i + 1));
      const b = hexVal(f.charCodeAt(i + 2));
      if (a < 0 || b < 0) return null;
      out += String.fromCharCode(a * 16 + b);
      i += 2;
    } else {
      return null;
    }
  }
  return out;
}

function groupLines(c: Compiled, r: Result, s: string): string[] {
  const lines: string[] = [];
  for (let g = 0; g <= c.ngroups; g++) {
    const name = c.groupNames[g];
    const label = name !== undefined ? `${g} (${name})` : `${g}`;
    const S = r.caps[2 * g];
    const E = r.caps[2 * g + 1];
    if (S < 0) lines.push(`${label}: unset`);
    else lines.push(`${label}: ${S}..${E} ${quoted(s.slice(S, E))}`);
  }
  return lines;
}

function findAll(m: Matcher, n: number): Result[] {
  const results: Result[] = [];
  let pos = 0;
  while (pos <= n) {
    const r = m.searchFrom(pos, false);
    if (r === null) break;
    results.push(r);
    pos = r.end > r.st ? r.end : r.end + 1;
  }
  return results;
}

function expand(repl: string, c: Compiled, r: Result, s: string): string {
  const groupText = (g: number): string => {
    const S = r.caps[2 * g];
    if (S < 0) return '';
    return s.slice(S, r.caps[2 * g + 1]);
  };
  let out = '';
  let i = 0;
  while (i < repl.length) {
    const ch = repl[i];
    if (ch !== '$') {
      out += ch;
      i++;
      continue;
    }
    if (i + 1 >= repl.length) {
      out += '$';
      i++;
      continue;
    }
    const nx = repl[i + 1];
    if (isDigitCode(nx.charCodeAt(0))) {
      const g = nx.charCodeAt(0) - 48;
      if (g > c.ngroups) fail('bad replacement');
      out += groupText(g);
      i += 2;
    } else if (nx === '$') {
      out += '$';
      i += 2;
    } else if (nx === '{') {
      const close = repl.indexOf('}', i + 2);
      if (close < 0) fail('bad replacement');
      const name = repl.slice(i + 2, close);
      let idx = -1;
      for (let g = 1; g <= c.ngroups; g++) {
        if (c.groupNames[g] === name) {
          idx = g;
          break;
        }
      }
      if (idx < 0) fail('bad replacement');
      out += groupText(idx);
      i = close + 1;
    } else {
      out += '$';
      i++;
    }
  }
  return out;
}

function execute(cmd: string, c: Compiled, s: string, repl: string): string[] {
  const m = new Matcher(c, s);
  switch (cmd) {
    case 'test':
      return [m.searchFrom(0, false) !== null ? 'true' : 'false'];
    case 'match':
    case 'full': {
      const r = m.searchFrom(0, cmd === 'full');
      if (r === null) return ['no match'];
      return groupLines(c, r, s);
    }
    case 'find-all': {
      const rs = findAll(m, s.length);
      const out = rs.map((r) => `${r.st}..${r.end} ${quoted(s.slice(r.st, r.end))}`);
      out.push(`(${rs.length} matches)`);
      return out;
    }
    case 'split': {
      const rs = findAll(m, s.length);
      const pieces: string[] = [];
      let prev = 0;
      for (const r of rs) {
        if (r.end > r.st) {
          pieces.push(s.slice(prev, r.st));
          prev = r.end;
        }
      }
      pieces.push(s.slice(prev));
      const out = pieces.map((p) => quoted(p));
      out.push(`(${pieces.length} pieces)`);
      return out;
    }
    default: {
      // replace
      const rs = findAll(m, s.length);
      let out = '';
      let last = 0;
      for (const r of rs) {
        out += s.slice(last, r.st);
        out += expand(repl, c, r, s);
        last = r.end;
      }
      out += s.slice(last);
      return [quoted(out)];
    }
  }
}

const COMMANDS = ['test', 'match', 'full', 'find-all', 'split', 'replace'];
const BAD = 'error: bad command';

function runCommand(line: string): string[] {
  const f = line.split('\t');
  const cmd = f[0];
  if (!COMMANDS.includes(cmd)) return [BAD];
  const want = cmd === 'replace' ? 4 : 3;
  if (f.length !== want) return [BAD];
  const subject = unescapeField(f[2]);
  if (subject === null) return [BAD];
  let repl = '';
  if (cmd === 'replace') {
    const r = unescapeField(f[3]);
    if (r === null) return [BAD];
    repl = r;
  }
  let compiled: Compiled;
  try {
    compiled = compile(f[1]);
  } catch (e) {
    if (e instanceof RegexError) return [`error: ${e.message}`];
    throw e;
  }
  try {
    return execute(cmd, compiled, subject, repl);
  } catch (e) {
    if (e instanceof RegexError) return [`error: ${e.message}`];
    throw e;
  }
}

function solve(input: string): string {
  const out: string[] = [];
  for (const line of input.split('\n')) {
    if (line === '') continue;
    for (const l of runCommand(line)) out.push(l);
  }
  return out.map((l) => l + '\n').join('');
}

// The matcher recurses once per repetition, so long subjects need a deep stack.
// Run the solver in a worker thread with a large stack; fall back to the main thread.
if (isMainThread) {
  const input = readFileSync(0).toString('latin1');
  let fellBack = false;
  const runHere = (): void => {
    if (fellBack) return;
    fellBack = true;
    process.stdout.write(solve(input));
  };
  try {
    const w = new Worker(new URL(import.meta.url), {
      workerData: input,
      resourceLimits: { stackSizeMb: 512 },
    });
    w.on('message', (out: string) => {
      if (fellBack) return;
      fellBack = true;
      process.stdout.write(out);
    });
    w.on('error', runHere);
    w.on('exit', () => runHere());
  } catch {
    runHere();
  }
} else {
  parentPort?.postMessage(solve(workerData as string));
}
