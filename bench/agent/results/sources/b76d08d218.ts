// Read stdin, write stdout. See TASK.md.
// jq-lite: a small jq-like interpreter.
import * as fs from 'node:fs';

// ---------- errors ----------
class JqError extends Error {
  value: any;
  constructor(value: any) {
    super(typeof value === 'string' ? value : 'jq error');
    this.value = value;
  }
}
class SyntaxErr extends Error {}
class CompileErr extends Error {}

function err(msg: string): never {
  throw new JqError(msg);
}

// ---------- value helpers ----------
function typeName(v: any): string {
  if (v === null) return 'null';
  if (typeof v === 'boolean') return 'boolean';
  if (typeof v === 'number') return 'number';
  if (typeof v === 'string') return 'string';
  if (Array.isArray(v)) return 'array';
  return 'object';
}

function typeRank(v: any): number {
  if (v === null) return 0;
  if (v === false) return 1;
  if (v === true) return 2;
  if (typeof v === 'number') return 3;
  if (typeof v === 'string') return 4;
  if (Array.isArray(v)) return 5;
  return 6;
}

function utf8Cmp(a: string, b: string): number {
  if (a === b) return 0;
  const ba = Buffer.from(a, 'utf8');
  const bb = Buffer.from(b, 'utf8');
  return Buffer.compare(ba, bb);
}

function sortedKeys(o: Map<string, any>): string[] {
  return [...o.keys()].sort(utf8Cmp);
}

function compare(a: any, b: any): number {
  const ra = typeRank(a);
  const rb = typeRank(b);
  if (ra !== rb) return ra < rb ? -1 : 1;
  switch (ra) {
    case 3: return a < b ? -1 : a > b ? 1 : 0;
    case 4: return utf8Cmp(a, b);
    case 5: {
      const n = Math.min(a.length, b.length);
      for (let i = 0; i < n; i++) {
        const c = compare(a[i], b[i]);
        if (c !== 0) return c;
      }
      return a.length < b.length ? -1 : a.length > b.length ? 1 : 0;
    }
    case 6: {
      const ka = sortedKeys(a);
      const kb = sortedKeys(b);
      const c = compare(ka, kb);
      if (c !== 0) return c;
      for (const k of ka) {
        const c2 = compare(a.get(k), b.get(k));
        if (c2 !== 0) return c2;
      }
      return 0;
    }
    default: return 0;
  }
}

function truthy(v: any): boolean {
  return !(v === null || v === false);
}

// ---------- number formatting ----------
function fmtNumber(n: number): string {
  if (Number.isNaN(n)) return 'null';
  if (n === Infinity) return '1.7976931348623157e+308';
  if (n === -Infinity) return '-1.7976931348623157e+308';
  if (Number.isInteger(n) && Math.abs(n) < 1e17) {
    return n === 0 ? '0' : String(n);
  }
  // shortest round-trip repr, expanded to plain notation
  let s = String(n);
  if (s.includes('e') || s.includes('E')) {
    const neg = s.startsWith('-');
    if (neg) s = s.slice(1);
    const [mant, expStr] = s.split('e');
    const exp = parseInt(expStr, 10);
    let [ip, fp = ''] = mant.split('.');
    let digits = ip + fp;
    let pointPos = ip.length + exp;
    let out: string;
    if (pointPos <= 0) {
      out = '0.' + '0'.repeat(-pointPos) + digits;
    } else if (pointPos >= digits.length) {
      out = digits + '0'.repeat(pointPos - digits.length);
    } else {
      out = digits.slice(0, pointPos) + '.' + digits.slice(pointPos);
    }
    out = out.replace(/^0+(?=\d)/, '');
    if (out.includes('.')) out = out.replace(/0+$/, '').replace(/\.$/, '');
    return (neg ? '-' : '') + out;
  }
  return s;
}

// ---------- string escaping ----------
function escStr(s: string): string {
  let out = '"';
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    const ch = s[i];
    if (ch === '"') out += '\\"';
    else if (ch === '\\') out += '\\\\';
    else if (ch === '\n') out += '\\n';
    else if (ch === '\t') out += '\\t';
    else if (ch === '\r') out += '\\r';
    else if (ch === '\b') out += '\\b';
    else if (ch === '\f') out += '\\f';
    else if (c < 0x20 || c === 0x7f) out += '\\u' + c.toString(16).padStart(4, '0');
    else out += ch;
  }
  return out + '"';
}

function toJson(v: any): string {
  if (v === null) return 'null';
  if (v === true) return 'true';
  if (v === false) return 'false';
  if (typeof v === 'number') return fmtNumber(v);
  if (typeof v === 'string') return escStr(v);
  if (Array.isArray(v)) return '[' + v.map(toJson).join(',') + ']';
  return '{' + [...(v as Map<string, any>).entries()].map(([k, x]) => escStr(k) + ':' + toJson(x)).join(',') + '}';
}

// ---------- JSON input parsing (strict) ----------
class JsonParser {
  s: string;
  i: number;
  constructor(s: string, i = 0) {
    this.s = s;
    this.i = i;
  }
  fail(): never {
    throw new SyntaxErr('invalid json');
  }
  ws() {
    const s = this.s;
    while (this.i < s.length) {
      const c = s[this.i];
      if (c === ' ' || c === '\t' || c === '\n' || c === '\r') this.i++;
      else break;
    }
  }
  value(depth = 0): any {
    if (depth > 10000) this.fail();
    this.ws();
    const s = this.s;
    if (this.i >= s.length) this.fail();
    const c = s[this.i];
    if (c === '{') {
      this.i++;
      const o = new Map<string, any>();
      this.ws();
      if (s[this.i] === '}') {
        this.i++;
        return o;
      }
      for (;;) {
        this.ws();
        if (s[this.i] !== '"') this.fail();
        const k = this.str();
        this.ws();
        if (s[this.i] !== ':') this.fail();
        this.i++;
        const v = this.value(depth + 1);
        o.set(k, v);
        this.ws();
        if (s[this.i] === ',') {
          this.i++;
          continue;
        }
        if (s[this.i] === '}') {
          this.i++;
          return o;
        }
        this.fail();
      }
    }
    if (c === '[') {
      this.i++;
      const a: any[] = [];
      this.ws();
      if (s[this.i] === ']') {
        this.i++;
        return a;
      }
      for (;;) {
        a.push(this.value(depth + 1));
        this.ws();
        if (s[this.i] === ',') {
          this.i++;
          continue;
        }
        if (s[this.i] === ']') {
          this.i++;
          return a;
        }
        this.fail();
      }
    }
    if (c === '"') return this.str();
    if (s.startsWith('true', this.i)) {
      this.i += 4;
      return true;
    }
    if (s.startsWith('false', this.i)) {
      this.i += 5;
      return false;
    }
    if (s.startsWith('null', this.i)) {
      this.i += 4;
      return null;
    }
    const re = /-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?/y;
    re.lastIndex = this.i;
    const m = re.exec(s);
    if (m) {
      this.i += m[0].length;
      if (/\d/.test(s[this.i] ?? '')) this.fail();
      return Number(m[0]);
    }
    this.fail();
  }
  str(): string {
    const s = this.s;
    this.i++; // opening quote
    let out = '';
    for (;;) {
      if (this.i >= s.length) this.fail();
      const c = s[this.i];
      const code = s.charCodeAt(this.i);
      if (c === '"') {
        this.i++;
        return out;
      }
      if (code < 0x20) this.fail();
      if (c === '\\') {
        const e = s[this.i + 1];
        this.i += 2;
        switch (e) {
          case '"': out += '"'; break;
          case '\\': out += '\\'; break;
          case '/': out += '/'; break;
          case 'b': out += '\b'; break;
          case 'f': out += '\f'; break;
          case 'n': out += '\n'; break;
          case 'r': out += '\r'; break;
          case 't': out += '\t'; break;
          case 'u': {
            const hex = s.slice(this.i, this.i + 4);
            if (!/^[0-9a-fA-F]{4}$/.test(hex)) this.fail();
            this.i += 4;
            out += decodeU(parseInt(hex, 16), this);
            break;
          }
          default: this.fail();
        }
      } else {
        out += c;
        this.i++;
      }
    }
  }
}

// Handles a \uXXXX escape (already consumed); combines surrogate pairs.
function decodeU(cp: number, p: JsonParser): string {
  if (cp >= 0xd800 && cp <= 0xdbff) {
    const s = p.s;
    if (s[p.i] === '\\' && s[p.i + 1] === 'u') {
      const hex = s.slice(p.i + 2, p.i + 6);
      if (/^[0-9a-fA-F]{4}$/.test(hex)) {
        const lo = parseInt(hex, 16);
        if (lo >= 0xdc00 && lo <= 0xdfff) {
          p.i += 6;
          return String.fromCharCode(cp, lo);
        }
      }
    }
    return '�';
  }
  if (cp >= 0xdc00 && cp <= 0xdfff) return '�';
  return String.fromCharCode(cp);
}

// Parse a whole text as exactly one JSON value (used by fromjson / tonumber-like helpers).
function parseOneJson(text: string): any {
  const p = new JsonParser(text);
  const v = p.value();
  p.ws();
  if (p.i !== text.length) p.fail();
  return v;
}

// Parse the stream of values in the input text. Calls cb per value; throws SyntaxErr on bad input
// after having delivered all earlier values.
function forEachJsonValue(text: string, cb: (v: any) => void): void {
  const p = new JsonParser(text);
  for (;;) {
    p.ws();
    if (p.i >= text.length) return;
    const v = p.value();
    cb(v);
  }
}


// ---------- lexer / parser ----------
const FORMATS = new Set(['text', 'json', 'csv', 'tsv', 'html', 'uri', 'base64', 'base64d']);
type Tok = { t: string; v?: any; s: number; e: number };

const KEYWORDS = new Set([
  'def', 'if', 'then', 'elif', 'else', 'end', 'as', 'reduce', 'foreach', 'try', 'catch',
  'and', 'or', 'label', 'import', 'include', '__loc__',
]);
const CMP_OPS = new Set(['==', '!=', '<', '<=', '>', '>=']);
const ASSIGN_OPS = new Set(['=', '|=', '+=', '-=', '*=', '/=', '%=', '//=']);
const IDSTART = /[A-Za-z_]/;
const IDCHAR = /[A-Za-z0-9_]/;

class Parser {
  src: string;
  pos = 0;
  lastEnd = 0;
  cache: { pos: number; tok: Tok } | null = null;
  constructor(src: string) {
    this.src = src;
  }
  fail(): never {
    throw new SyntaxErr('syntax error');
  }
  skipWs() {
    const s = this.src;
    while (this.pos < s.length && ' \t\n\r'.includes(s[this.pos])) this.pos++;
  }
  peek(): Tok {
    if (this.cache && this.cache.pos === this.pos) return this.cache.tok;
    const save = this.pos;
    this.skipWs();
    const tok = this.lexOne();
    const end = this.pos;
    this.pos = save;
    const t: Tok = { ...tok, e: end };
    this.cache = { pos: save, tok: t };
    return t;
  }
  next(): Tok {
    const t = this.peek();
    this.pos = t.e;
    this.lastEnd = t.e;
    return t;
  }
  isOp(v: string): boolean {
    const t = this.peek();
    return t.t === 'op' && t.v === v;
  }
  isId(v: string): boolean {
    const t = this.peek();
    return t.t === 'id' && t.v === v;
  }
  expectOp(v: string) {
    if (!this.isOp(v)) this.fail();
    this.next();
  }
  expectId(v: string) {
    if (!this.isId(v)) this.fail();
    this.next();
  }
  // Called with this.pos at a token start (whitespace already skipped). Sets this.pos to token end.
  lexOne(): Omit<Tok, 'e'> {
    const s = this.src;
    const i = this.pos;
    const start = i;
    if (i >= s.length) return { t: 'eof', s: i };
    const c = s[i];
    if (c === '"') return this.lexString(i);
    if (/[0-9]/.test(c) || (c === '.' && /[0-9]/.test(s[i + 1] ?? ''))) {
      const re = /(\d+(\.\d+)?|\.\d+)([eE][+-]?\d+)?/y;
      re.lastIndex = i;
      const m = re.exec(s);
      if (!m) this.fail();
      this.pos = i + m[0].length;
      return { t: 'num', v: Number(m[0]), s: start };
    }
    if (c === '$' && IDSTART.test(s[i + 1] ?? '')) {
      let j = i + 1;
      while (j < s.length && IDCHAR.test(s[j])) j++;
      this.pos = j;
      return { t: 'var', v: s.slice(i + 1, j), s: start };
    }
    if (c === '@' && IDSTART.test(s[i + 1] ?? '')) {
      let j = i + 1;
      while (j < s.length && IDCHAR.test(s[j])) j++;
      this.pos = j;
      return { t: 'fmt', v: s.slice(i + 1, j), s: start };
    }
    if (IDSTART.test(c)) {
      let j = i;
      while (j < s.length && IDCHAR.test(s[j])) j++;
      this.pos = j;
      return { t: 'id', v: s.slice(i, j), s: start };
    }
    if (c === '.') {
      if (s[i + 1] === '.') {
        this.pos = i + 2;
        return { t: 'op', v: '..', s: start };
      }
      if (IDSTART.test(s[i + 1] ?? '')) {
        let j = i + 1;
        while (j < s.length && IDCHAR.test(s[j])) j++;
        this.pos = j;
        return { t: 'field', v: s.slice(i + 1, j), s: start };
      }
      this.pos = i + 1;
      return { t: 'op', v: '.', s: start };
    }
    for (const op of ['//=', '//', '|=', '+=', '-=', '*=', '/=', '%=', '==', '!=', '<=', '>=']) {
      if (s.startsWith(op, i)) {
        this.pos = i + op.length;
        return { t: 'op', v: op, s: start };
      }
    }
    if ('|,()[]{}:;=<>+-*/%?'.includes(c)) {
      this.pos = i + 1;
      return { t: 'op', v: c, s: start };
    }
    this.fail();
  }
  lexString(start: number): Omit<Tok, 'e'> {
    const s = this.src;
    let i = start + 1;
    const parts: (string | any)[] = [];
    let buf = '';
    for (;;) {
      if (i >= s.length) this.fail();
      const c = s[i];
      if (c === '"') {
        i++;
        break;
      }
      if (c === '\\') {
        const e = s[i + 1];
        if (e === '(') {
          parts.push(buf);
          buf = '';
          this.pos = i + 2;
          const node = this.parsePipe();
          this.expectOp(')');
          parts.push(node);
          i = this.pos;
          continue;
        }
        i += 2;
        switch (e) {
          case '"': buf += '"'; break;
          case '\\': buf += '\\'; break;
          case '/': buf += '/'; break;
          case 'b': buf += '\b'; break;
          case 'f': buf += '\f'; break;
          case 'n': buf += '\n'; break;
          case 'r': buf += '\r'; break;
          case 't': buf += '\t'; break;
          case 'u': {
            const hex = s.slice(i, i + 4);
            if (!/^[0-9a-fA-F]{4}$/.test(hex)) this.fail();
            i += 4;
            const cp = parseInt(hex, 16);
            if (cp >= 0xd800 && cp <= 0xdbff && s[i] === '\\' && s[i + 1] === 'u' && /^[0-9a-fA-F]{4}$/.test(s.slice(i + 2, i + 6))) {
              const lo = parseInt(s.slice(i + 2, i + 6), 16);
              if (lo >= 0xdc00 && lo <= 0xdfff) {
                buf += String.fromCharCode(cp, lo);
                i += 6;
                break;
              }
            }
            if (cp >= 0xd800 && cp <= 0xdfff) buf += '�';
            else buf += String.fromCharCode(cp);
            break;
          }
          default: this.fail();
        }
        continue;
      }
      buf += c;
      i++;
    }
    parts.push(buf);
    this.pos = i;
    return { t: 'str', v: parts, s: start };
  }

  // ----- grammar -----
  parseProgram(): any {
    const n = this.parsePipe();
    if (this.peek().t !== 'eof') this.fail();
    return n;
  }
  parsePipe(): any {
    if (this.isId('def')) {
      const d = this.parseDef();
      const rest = this.parsePipe();
      return { ...d, rest };
    }
    const l = this.parseComma();
    if (this.isOp('|')) {
      this.next();
      const r = this.parsePipe();
      return { k: 'pipe', l, r };
    }
    return l;
  }
  parseDef(): any {
    this.expectId('def');
    const nt = this.next();
    if (nt.t !== 'id' || KEYWORDS.has(nt.v)) this.fail();
    const params: { name: string; isVar: boolean }[] = [];
    if (this.isOp('(')) {
      this.next();
      for (;;) {
        const t = this.next();
        if (t.t === 'id' && !KEYWORDS.has(t.v)) params.push({ name: t.v, isVar: false });
        else if (t.t === 'var') params.push({ name: t.v, isVar: true });
        else this.fail();
        if (this.isOp(';')) {
          this.next();
          continue;
        }
        this.expectOp(')');
        break;
      }
    }
    this.expectOp(':');
    const body = this.parsePipe();
    this.expectOp(';');
    return { k: 'def', name: nt.v, params, body };
  }
  parseComma(): any {
    let l = this.parseAlt();
    while (this.isOp(',')) {
      this.next();
      const r = this.parseAlt();
      l = { k: 'comma', l, r };
    }
    return l;
  }
  parseAlt(): any {
    const l = this.parseAssign();
    if (this.isOp('//')) {
      this.next();
      const r = this.parseAlt();
      return { k: 'alt', l, r };
    }
    return l;
  }
  parseAssign(): any {
    const l = this.parseOr();
    const t = this.peek();
    if (t.t === 'op' && ASSIGN_OPS.has(t.v)) {
      this.next();
      const r = this.parseOr();
      return { k: 'assign', op: t.v, l, r };
    }
    return l;
  }
  parseOr(): any {
    let l = this.parseAnd();
    while (this.isId('or')) {
      this.next();
      l = { k: 'or', l, r: this.parseAnd() };
    }
    return l;
  }
  parseAnd(): any {
    let l = this.parseCmp();
    while (this.isId('and')) {
      this.next();
      l = { k: 'and', l, r: this.parseCmp() };
    }
    return l;
  }
  parseCmp(): any {
    const l = this.parseAdd();
    const t = this.peek();
    if (t.t === 'op' && CMP_OPS.has(t.v)) {
      this.next();
      const r = this.parseAdd();
      return { k: 'bin', op: t.v, l, r };
    }
    return l;
  }
  parseAdd(): any {
    let l = this.parseMul();
    for (;;) {
      const t = this.peek();
      if (t.t === 'op' && (t.v === '+' || t.v === '-')) {
        this.next();
        l = { k: 'bin', op: t.v, l, r: this.parseMul() };
      } else return l;
    }
  }
  parseMul(): any {
    let l = this.parseUnary();
    for (;;) {
      const t = this.peek();
      if (t.t === 'op' && (t.v === '*' || t.v === '/' || t.v === '%')) {
        this.next();
        l = { k: 'bin', op: t.v, l, r: this.parseUnary() };
      } else return l;
    }
  }
  parseUnary(): any {
    if (this.isOp('-')) {
      this.next();
      return { k: 'neg', e: this.parseUnary() };
    }
    return this.parsePostfix(true);
  }
  parsePostfix(allowAs: boolean): any {
    let t = this.parsePrimary();
    for (;;) {
      const tok = this.peek();
      if (tok.s !== this.lastEnd) return t;
      if (tok.t === 'field') {
        this.next();
        t = { k: 'index', t, idx: { k: 'lit', v: tok.v } };
      } else if (tok.t === 'op' && tok.v === '.') {
        // ."str" or .[ handled as ".": only ."str" is a suffix here
        const save = this.pos;
        this.next();
        const st = this.peek();
        if (st.t === 'str' && st.s === this.lastEnd) {
          this.next();
          t = { k: 'index', t, idx: this.strNode(st.v, null) };
        } else if (this.isOp('[') && this.peek().s === this.lastEnd) {
          // .[ after a term: fall through to bracket handling
          continue;
        } else {
          this.pos = save;
          this.lastEnd = save;
          return t;
        }
      } else if (tok.t === 'op' && tok.v === '[') {
        this.next();
        t = this.parseBracket(t);
      } else if (tok.t === 'op' && tok.v === '?') {
        this.next();
        t = { k: 'try', body: t, handler: null };
      } else if (tok.t === 'id' && tok.v === 'as' && allowAs) {
        this.next();
        const pats = [this.parsePattern()];
        while (this.isOp('?')) this.fail();
        this.expectOp('|');
        const body = this.parsePipe();
        return { k: 'as', src: t, pats, body };
      } else {
        return t;
      }
    }
  }
  parseBracket(t: any): any {
    // '[' already consumed
    if (this.isOp(']')) {
      this.next();
      return { k: 'iter', t };
    }
    if (this.isOp(':')) {
      this.next();
      const to = this.parsePipe();
      this.expectOp(']');
      return { k: 'slice', t, from: null, to };
    }
    const e = this.parsePipe();
    if (this.isOp(':')) {
      this.next();
      let to: any = null;
      if (!this.isOp(']')) to = this.parsePipe();
      this.expectOp(']');
      return { k: 'slice', t, from: e, to };
    }
    this.expectOp(']');
    return { k: 'index', t, idx: e };
  }
  strNode(parts: any[], fmt: string | null): any {
    if (parts.length === 1 && typeof parts[0] === 'string') return { k: 'lit', v: parts[0] };
    return { k: 'str', parts, fmt };
  }
  parsePrimary(): any {
    const t = this.next();
    switch (t.t) {
      case 'num': return { k: 'lit', v: t.v };
      case 'str': return this.strNode(t.v, null);
      case 'fmt': {
        if (!FORMATS.has(t.v)) this.fail();
        if (this.peek().t === 'str' && this.peek().s === this.lastEnd) {
          const st = this.next();
          return this.strNode(st.v, t.v);
        }
        return { k: 'fmt', name: t.v };
      }
      case 'field': return { k: 'index', t: { k: 'id' }, idx: { k: 'lit', v: t.v } };
      case 'var': return { k: 'var', name: t.v };
      case 'op': {
        if (t.v === '.') {
          const st = this.peek();
          if (st.t === 'str' && st.s === this.lastEnd) {
            this.next();
            return { k: 'index', t: { k: 'id' }, idx: this.strNode(st.v, null) };
          }
          return { k: 'id' };
        }
        if (t.v === '..') return { k: 'call', name: 'recurse', args: [] };
        if (t.v === '(') {
          const e = this.parsePipe();
          this.expectOp(')');
          return e;
        }
        if (t.v === '[') {
          if (this.isOp(']')) {
            this.next();
            return { k: 'arr', body: null };
          }
          const body = this.parsePipe();
          this.expectOp(']');
          return { k: 'arr', body };
        }
        if (t.v === '{') return this.parseObject();
        if (t.v === '-') return { k: 'neg', e: this.parsePostfix(false) };
        this.fail();
      }
      case 'id': {
        const v = t.v;
        if (v === 'if') return this.parseIf();
        if (v === 'try') {
          const body = this.parsePostfixNoAs();
          let handler = null;
          if (this.isId('catch')) {
            this.next();
            handler = this.parsePostfixNoAs();
          }
          return { k: 'try', body, handler };
        }
        if (v === 'reduce') {
          const src = this.parsePostfix(false);
          this.expectId('as');
          const pat = this.parsePattern();
          this.expectOp('(');
          const init = this.parsePipe();
          this.expectOp(';');
          const upd = this.parsePipe();
          this.expectOp(')');
          return { k: 'reduce', src, pat, init, upd };
        }
        if (v === 'foreach') {
          const src = this.parsePostfix(false);
          this.expectId('as');
          const pat = this.parsePattern();
          this.expectOp('(');
          const init = this.parsePipe();
          this.expectOp(';');
          const upd = this.parsePipe();
          let ext = null;
          if (this.isOp(';')) {
            this.next();
            ext = this.parsePipe();
          }
          this.expectOp(')');
          return { k: 'foreach', src, pat, init, upd, ext };
        }
        if (v === 'def') {
          this.pos = t.s;
          this.cache = null;
          const d = this.parseDef();
          const rest = this.parsePipe();
          return { ...d, rest };
        }
        if (v === 'true') return { k: 'lit', v: true };
        if (v === 'false') return { k: 'lit', v: false };
        if (v === 'null') return { k: 'lit', v: null };
        if (KEYWORDS.has(v)) this.fail();
        const args: any[] = [];
        if (this.isOp('(')) {
          this.next();
          for (;;) {
            args.push(this.parsePipe());
            if (this.isOp(';')) {
              this.next();
              continue;
            }
            this.expectOp(')');
            break;
          }
        }
        return { k: 'call', name: v, args };
      }
      default:
        this.fail();
    }
  }
  parsePostfixNoAs(): any {
    return this.parsePostfix(false);
  }
  parseIf(): any {
    const c = this.parsePipe();
    this.expectId('then');
    const th = this.parsePipe();
    if (this.isId('elif')) {
      this.next();
      const el = this.parseIf(); // consumes through 'end'
      return { k: 'if', c, t: th, e: el };
    }
    let el: any = { k: 'id' };
    if (this.isId('else')) {
      this.next();
      el = this.parsePipe();
    }
    this.expectId('end');
    return { k: 'if', c, t: th, e: el };
  }
  parseObjVal(): any {
    let l = this.parseAlt();
    while (this.isOp('|')) {
      this.next();
      l = { k: 'pipe', l, r: this.parseAlt() };
    }
    return l;
  }
  parseObject(): any {
    const entries: { key: any; val: any }[] = [];
    if (this.isOp('}')) {
      this.next();
      return { k: 'obj', entries };
    }
    for (;;) {
      const t = this.next();
      let key: any;
      let val: any = null;
      if (t.t === 'var') {
        key = { k: 'lit', v: t.v };
        val = { k: 'var', name: t.v };
      } else if (t.t === 'id') {
        key = { k: 'lit', v: t.v };
        if (this.isOp(':')) {
          this.next();
          val = this.parseObjVal();
        } else {
          val = { k: 'index', t: { k: 'id' }, idx: key };
        }
      } else if (t.t === 'num') {
        this.fail();
      } else if (t.t === 'str') {
        key = this.strNode(t.v, null);
        if (this.isOp(':')) {
          this.next();
          val = this.parseObjVal();
        } else {
          val = { k: 'index', t: { k: 'id' }, idx: key };
        }
      } else if (t.t === 'fmt') {
        if (this.peek().t !== 'str') this.fail();
        const st = this.next();
        key = this.strNode(st.v, t.v);
        this.expectOp(':');
        val = this.parseObjVal();
      } else if (t.t === 'op' && t.v === '(') {
        key = this.parsePipe();
        this.expectOp(')');
        this.expectOp(':');
        val = this.parseObjVal();
      } else {
        this.fail();
      }
      entries.push({ key, val });
      if (this.isOp(',')) {
        this.next();
        if (this.isOp('}')) {
          this.next();
          break;
        }
        continue;
      }
      this.expectOp('}');
      break;
    }
    return { k: 'obj', entries };
  }
  parsePattern(): any {
    const t = this.next();
    if (t.t === 'var') return { k: 'pvar', name: t.v };
    if (t.t === 'op' && t.v === '[') {
      const elems: any[] = [];
      for (;;) {
        elems.push(this.parsePattern());
        if (this.isOp(',')) {
          this.next();
          continue;
        }
        this.expectOp(']');
        break;
      }
      return { k: 'parr', elems };
    }
    if (t.t === 'op' && t.v === '{') {
      const entries: { key: any; var: string | null; pat: any }[] = [];
      for (;;) {
        const kt = this.next();
        if (kt.t === 'var') {
          let pat = null;
          if (this.isOp(':')) {
            this.next();
            pat = this.parsePattern();
          }
          entries.push({ key: { k: 'lit', v: kt.v }, var: kt.v, pat });
        } else {
          let key: any;
          if (kt.t === 'id') key = { k: 'lit', v: kt.v };
          else if (kt.t === 'str') key = this.strNode(kt.v, null);
          else if (kt.t === 'op' && kt.v === '(') {
            key = this.parsePipe();
            this.expectOp(')');
          } else this.fail();
          this.expectOp(':');
          entries.push({ key, var: null, pat: this.parsePattern() });
        }
        if (this.isOp(',')) {
          this.next();
          continue;
        }
        this.expectOp('}');
        break;
      }
      return { k: 'pobj', entries };
    }
    this.fail();
  }
}

function parseProgram(src: string): any {
  const p = new Parser(src);
  return p.parseProgram();
}

// ---------- environments ----------
type Env = any;
function lookupVar(env: Env, name: string): any {
  for (let e = env; e; e = e.next) if (e.kind === 'var' && e.name === name) return e.value;
  err(`$${name} is not defined`);
}
function lookupFunc(env: Env, name: string, arity: number): any {
  for (let e = env; e; e = e.next) if (e.kind === 'func' && e.name === name && e.arity === arity) return e;
  return undefined;
}
function bindDef(n: any, env: Env): Env {
  const node: any = { kind: 'func', name: n.name, arity: n.params.length, params: n.params, body: n.body, next: env, env: null };
  node.env = node;
  return node;
}

// ---------- object / index helpers ----------
type JObj = Map<string, any>;
function getKey(o: JObj, k: string): any {
  return o.has(k) ? o.get(k) : null;
}
function indexValue(b: any, k: any): any {
  if (b === null) {
    if (typeof k === 'string' || typeof k === 'number' || k === null) return null;
    err(`Cannot index null with ${typeName(k)}`);
  }
  if (b instanceof Map) {
    if (typeof k !== 'string') err(`Cannot index object with ${typeName(k)}`);
    return getKey(b, k);
  }
  if (Array.isArray(b)) {
    if (typeof k === 'number') {
      let idx = Math.floor(k);
      if (idx < 0) idx += b.length;
      return idx >= 0 && idx < b.length ? b[idx] : null;
    }
    if (typeof k === 'string') err(`Cannot index array with string ${escStr(k)}`);
    err(`Cannot index array with ${typeName(k)}`);
  }
  if (typeof k === 'string') err(`Cannot index ${typeName(b)} with string ${escStr(k)}`);
  err(`Cannot index ${typeName(b)} with ${typeName(k)}`);
}
function sliceValue(v: any, a: any, b: any): any {
  if (v === null) return null;
  if (!(typeof v === 'string' || Array.isArray(v))) err(`Cannot index ${typeName(v)} with object`);
  if ((a !== null && typeof a !== 'number') || (b !== null && typeof b !== 'number')) {
    err('Start and end indices of an array slice must be numbers');
  }
  const isStr = typeof v === 'string';
  const chars = isStr ? Array.from(v as string) : null;
  const len = isStr ? chars!.length : (v as any[]).length;
  let start = a === null ? 0 : Math.floor(a);
  let end = b === null ? len : Math.ceil(b);
  if (start < 0) start += len;
  if (end < 0) end += len;
  start = Math.min(Math.max(start, 0), len);
  end = Math.min(Math.max(end, 0), len);
  if (end < start) end = start;
  if (isStr) return chars!.slice(start, end).join('');
  return (v as any[]).slice(start, end);
}
function* iterateValues(b: any): Generator<any> {
  if (Array.isArray(b)) {
    for (let i = 0; i < b.length; i++) yield b[i];
    return;
  }
  if (b instanceof Map) {
    for (const v of b.values()) yield v;
    return;
  }
  err(`Cannot iterate over ${typeName(b)}`);
}

// ---------- generic depth-first driver (for recursion-like builtins) ----------
type Item = { out: any } | { visit: any };
function* dfs(root: any, step: (x: any) => Iterable<Item>): Generator<any> {
  const stack: Iterator<Item>[] = [step(root)[Symbol.iterator]()];
  while (stack.length) {
    const r = stack[stack.length - 1].next();
    if (r.done) {
      stack.pop();
      continue;
    }
    const it: any = r.value;
    if ('out' in it) yield it.out;
    else stack.push(step(it.visit)[Symbol.iterator]());
  }
}

// ---------- pattern binding ----------
function* bindPat(pat: any, v: any, input: any, env: Env): Generator<Env> {
  switch (pat.k) {
    case 'pvar':
      yield { kind: 'var', name: pat.name, value: v, next: env };
      return;
    case 'parr': {
      if (v !== null && !Array.isArray(v)) err(`Cannot index ${typeName(v)} with number`);
      const rec = function* (i: number, e: Env): Generator<Env> {
        if (i === pat.elems.length) {
          yield e;
          return;
        }
        const elem = v === null ? null : indexValue(v, i);
        for (const e2 of bindPat(pat.elems[i], elem, input, e)) yield* rec(i + 1, e2);
      };
      yield* rec(0, env);
      return;
    }
    case 'pobj': {
      const rec = function* (i: number, e: Env): Generator<Env> {
        if (i === pat.entries.length) {
          yield e;
          return;
        }
        const ent = pat.entries[i];
        for (const kv of ev(ent.key, input, e)) {
          if (typeof kv !== 'string') err(`Cannot index ${typeName(v)} with ${typeName(kv)}`);
          if (v !== null && !(v instanceof Map)) err(`Cannot index ${typeName(v)} with string ${escStr(kv)}`);
          const val = v === null ? null : getKey(v, kv);
          let e2: Env = e;
          if (ent.var) e2 = { kind: 'var', name: ent.var, value: val, next: e2 };
          if (ent.pat) {
            for (const e3 of bindPat(ent.pat, val, input, e2)) yield* rec(i + 1, e3);
          } else yield* rec(i + 1, e2);
        }
      };
      yield* rec(0, env);
      return;
    }
    default:
      err('bad pattern');
  }
}

// ---------- function calls ----------
function* bindParams(fn: any, i: number, args: any[], input: any, callerEnv: Env, acc: Env, run: (e: Env) => Iterable<any>): Generator<any> {
  if (i === fn.params.length) {
    yield* run(acc);
    return;
  }
  const p = fn.params[i];
  if (!p.isVar) {
    yield* bindParams(fn, i + 1, args, input, callerEnv,
      { kind: 'func', name: p.name, arity: 0, body: args[i], env: callerEnv, closure: true, next: acc }, run);
    return;
  }
  for (const v of ev(args[i], input, callerEnv)) {
    const e1 = { kind: 'var', name: p.name, value: v, next: acc };
    const e2 = { kind: 'func', name: p.name, arity: 0, body: { k: 'lit', v }, env: null, closure: true, next: e1 };
    yield* bindParams(fn, i + 1, args, input, callerEnv, e2, run);
  }
}

// Native table: filled in later. Each entry: (input, argNodes, env) => iterable.
const natives: Record<string, (input: any, args: any[], env: Env) => Iterable<any>> = {};
const pathNatives: Record<string, (cur: PathVal, args: any[], env: Env) => Iterable<PathVal>> = {};

function* evCall(n: any, input: any, env: Env): Generator<any> {
  const arity = n.args.length;
  const fn = lookupFunc(env, n.name, arity);
  if (fn) {
    if (fn.closure) {
      yield* ev(fn.body, input, fn.env);
      return;
    }
    yield* bindParams(fn, 0, n.args, input, env, fn.env, (e) => ev(fn.body, input, e));
    return;
  }
  const nat = natives[`${n.name}/${arity}`];
  if (nat) {
    yield* nat(input, n.args, env);
    return;
  }
  err(`${n.name}/${arity} is not defined`);
}

// ---------- value-mode evaluation ----------
function* ev(n: any, input: any, env: Env): Generator<any> {
  switch (n.k) {
    case 'id':
      yield input;
      return;
    case 'lit':
      yield n.v;
      return;
    case 'index':
      for (const k of ev(n.idx, input, env)) for (const b of ev(n.t, input, env)) yield indexValue(b, k);
      return;
    case 'slice':
      for (const a of n.from ? ev(n.from, input, env) : [null])
        for (const b of n.to ? ev(n.to, input, env) : [null])
          for (const v of ev(n.t, input, env)) yield sliceValue(v, a, b);
      return;
    case 'iter':
      for (const b of ev(n.t, input, env)) yield* iterateValues(b);
      return;
    case 'pipe':
      for (const a of ev(n.l, input, env)) yield* ev(n.r, a, env);
      return;
    case 'comma':
      yield* ev(n.l, input, env);
      yield* ev(n.r, input, env);
      return;
    case 'neg':
      for (const v of ev(n.e, input, env)) {
        if (typeof v !== 'number') err(`${typeName(v)} cannot be negated`);
        yield -v;
      }
      return;
    case 'bin':
      for (const b of ev(n.r, input, env)) for (const a of ev(n.l, input, env)) yield binop(n.op, a, b);
      return;
    case 'and':
      for (const a of ev(n.l, input, env)) {
        if (!truthy(a)) {
          yield false;
          continue;
        }
        for (const b of ev(n.r, input, env)) yield truthy(b);
      }
      return;
    case 'or':
      for (const a of ev(n.l, input, env)) {
        if (truthy(a)) {
          yield true;
          continue;
        }
        for (const b of ev(n.r, input, env)) yield truthy(b);
      }
      return;
    case 'alt': {
      let any = false;
      try {
        for (const a of ev(n.l, input, env)) {
          if (truthy(a)) {
            any = true;
            yield a;
          }
        }
      } catch (e) {
        if (!(e instanceof JqError)) throw e;
      }
      if (!any) yield* ev(n.r, input, env);
      return;
    }
    case 'if':
      for (const c of ev(n.c, input, env)) yield* ev(truthy(c) ? n.t : n.e, input, env);
      return;
    case 'try':
      try {
        for (const v of ev(n.body, input, env)) yield v;
      } catch (e) {
        if (!(e instanceof JqError)) throw e;
        if (n.handler) yield* ev(n.handler, e.value, env);
      }
      return;
    case 'arr': {
      const out: any[] = [];
      if (n.body) for (const v of ev(n.body, input, env)) out.push(v);
      yield out;
      return;
    }
    case 'obj':
      yield* evObj(n.entries, 0, input, env);
      return;
    case 'str':
      yield* evStr(n, input, env);
      return;
    case 'fmt':
      yield fmtApply(n.name, input);
      return;
    case 'var':
      yield lookupVar(env, n.name);
      return;
    case 'call':
      yield* evCall(n, input, env);
      return;
    case 'as':
      for (const v of ev(n.src, input, env))
        for (const e of bindPat(n.pat, v, input, env)) yield* ev(n.body, input, e);
      return;
    case 'reduce':
      for (const init of ev(n.init, input, env)) {
        let st = init;
        for (const v of ev(n.src, input, env))
          for (const e of bindPat(n.pat, v, input, env)) {
            let last: any = null;
            for (const u of ev(n.upd, st, e)) last = u;
            st = last;
          }
        yield st;
      }
      return;
    case 'foreach':
      for (const init of ev(n.init, input, env)) {
        let st = init;
        for (const v of ev(n.src, input, env))
          for (const e of bindPat(n.pat, v, input, env)) {
            let has = false;
            let lastU: any = null;
            for (const u of ev(n.upd, st, e)) {
              has = true;
              lastU = u;
              if (n.ext) yield* ev(n.ext, u, e);
              else yield u;
            }
            if (has) st = lastU;
          }
      }
      return;
    case 'def':
      yield* ev(n.rest, input, bindDef(n, env));
      return;
    case 'assign':
      yield* evAssign(n, input, env);
      return;
    default:
      err(`unknown node ${n.k}`);
  }
}

function* evObj(entries: any[], i: number, input: any, env: Env): Generator<JObj> {
  // Build combinations; later entries are the outer loop, earlier ones vary fastest.
  let L: [any, any][][] = [[]];
  for (let j = entries.length - 1; j >= 0; j--) {
    const ks = [...ev(entries[j].key, input, env)];
    const vs = [...ev(entries[j].val, input, env)];
    const next: [any, any][][] = [];
    for (const prev of L)
      for (const k of ks) {
        if (typeof k !== 'string') err('Object keys must be strings');
        for (const v of vs) next.push([[k, v], ...prev]);
      }
    L = next;
  }
  for (const combo of L) {
    const m: JObj = new Map();
    for (const [k, v] of combo) m.set(k, v);
    yield m;
  }
}

function* evStr(n: any, input: any, env: Env): Generator<string> {
  let L: string[] = [''];
  for (let j = n.parts.length - 1; j >= 0; j--) {
    const part = n.parts[j];
    if (typeof part === 'string') {
      L = L.map((s) => part + s);
      continue;
    }
    const vals = [...ev(part, input, env)].map((v) => (n.fmt ? fmtApply(n.fmt, v) : tostr(v)));
    const next: string[] = [];
    for (const s of L) for (const v of vals) next.push(v + s);
    L = next;
  }
  for (const s of L) yield s;
}

function tostr(v: any): string {
  return typeof v === 'string' ? v : toJson(v);
}

// ---------- path-mode evaluation ----------
type PathVal = { p: any[]; v: any };
function invalidPath(v: any): never {
  err(`Invalid path expression with result ${toJson(v)}`);
}
function* evalPath(n: any, cur: PathVal, env: Env): Generator<PathVal> {
  switch (n.k) {
    case 'id':
      yield cur;
      return;
    case 'index':
      for (const k of ev(n.idx, cur.v, env))
        for (const b of evalPath(n.t, cur, env)) yield { p: [...b.p, k], v: indexValue(b.v, k) };
      return;
    case 'iter':
      for (const b of evalPath(n.t, cur, env)) {
        if (Array.isArray(b.v)) {
          for (let i = 0; i < b.v.length; i++) yield { p: [...b.p, i], v: b.v[i] };
        } else if (b.v instanceof Map) {
          for (const [k, v] of b.v) yield { p: [...b.p, k], v };
        } else err(`Cannot iterate over ${typeName(b.v)}`);
      }
      return;
    case 'slice':
      err('Slices are not supported in path expressions');
      return;
    case 'pipe':
      for (const a of evalPath(n.l, cur, env)) yield* evalPath(n.r, a, env);
      return;
    case 'comma':
      yield* evalPath(n.l, cur, env);
      yield* evalPath(n.r, cur, env);
      return;
    case 'if':
      for (const c of ev(n.c, cur.v, env)) yield* evalPath(truthy(c) ? n.t : n.e, cur, env);
      return;
    case 'alt': {
      let any = false;
      try {
        for (const a of evalPath(n.l, cur, env)) {
          if (truthy(a.v)) {
            any = true;
            yield a;
          }
        }
      } catch (e) {
        if (!(e instanceof JqError)) throw e;
      }
      if (!any) yield* evalPath(n.r, cur, env);
      return;
    }
    case 'try':
      try {
        for (const a of evalPath(n.body, cur, env)) yield a;
      } catch (e) {
        if (!(e instanceof JqError)) throw e;
        if (n.handler) yield* evalPath(n.handler, { p: cur.p, v: e.value }, env);
      }
      return;
    case 'call':
      yield* evalPathCall(n, cur, env);
      return;
    case 'as':
      for (const v of ev(n.src, cur.v, env))
        for (const e of bindPat(n.pat, v, cur.v, env)) yield* evalPath(n.body, cur, e);
      return;
    case 'def':
      yield* evalPath(n.rest, cur, bindDef(n, env));
      return;
    default:
      for (const v of ev(n, cur.v, env)) invalidPath(v);
      return;
  }
}

function* evalPathCall(n: any, cur: PathVal, env: Env): Generator<PathVal> {
  const arity = n.args.length;
  const fn = lookupFunc(env, n.name, arity);
  if (fn) {
    if (fn.closure) {
      yield* evalPath(fn.body, cur, fn.env);
      return;
    }
    yield* bindParams(fn, 0, n.args, cur.v, env, fn.env, (e) => evalPath(fn.body, cur, e));
    return;
  }
  const key = `${n.name}/${arity}`;
  const pn = pathNatives[key];
  if (pn) {
    yield* pn(cur, n.args, env);
    return;
  }
  const nat = natives[key];
  if (!nat) err(`${key} is not defined`);
  for (const v of nat(cur.v, n.args, env)) invalidPath(v);
}

// ---------- assignment ----------
function* pathsOf(l: any, input: any, env: Env): Generator<any[]> {
  for (const x of evalPath(l, { p: [], v: input }, env)) yield x.p;
}

function* evAssign(n: any, input: any, env: Env): Generator<any> {
  const paths = [...pathsOf(n.l, input, env)];
  if (n.op === '=') {
    for (const r of ev(n.r, input, env)) {
      let res = input;
      for (const p of paths) res = setPath(res, p, r);
      yield res;
    }
    return;
  }
  if (n.op === '|=') {
    let res = input;
    const dels: any[][] = [];
    for (const p of paths) {
      const old = getPath(res, p);
      let got = false;
      let nv: any = null;
      for (const v of ev(n.r, old, env)) {
        nv = v;
        got = true;
        break;
      }
      if (got) res = setPath(res, p, nv);
      else dels.push(p);
    }
    if (dels.length) res = delPaths(res, dels);
    yield res;
    return;
  }
  const op = n.op.slice(0, -1); // '+', '-', '*', '/', '%', '//'
  for (const r of ev(n.r, input, env)) {
    let res = input;
    for (const p of paths) {
      const old = getPath(res, p);
      const nv = op === '//' ? (truthy(old) ? old : r) : binop(op, old, r);
      res = setPath(res, p, nv);
    }
    yield res;
  }
}

// ---------- operators ----------
function deepMerge(a: JObj, b: JObj): JObj {
  const m: JObj = new Map(a);
  for (const [k, v] of b) {
    const old = m.get(k);
    if (old instanceof Map && v instanceof Map) m.set(k, deepMerge(old, v));
    else m.set(k, v);
  }
  return m;
}
function splitStr(s: string, sep: string): string[] {
  if (s === '') return [];
  if (sep === '') return Array.from(s);
  return s.split(sep);
}
function binop(op: string, a: any, b: any): any {
  switch (op) {
    case '==': return compare(a, b) === 0;
    case '!=': return compare(a, b) !== 0;
    case '<': return compare(a, b) < 0;
    case '<=': return compare(a, b) <= 0;
    case '>': return compare(a, b) > 0;
    case '>=': return compare(a, b) >= 0;
    case '+':
      if (a === null) return b;
      if (b === null) return a;
      if (typeof a === 'number' && typeof b === 'number') return a + b;
      if (typeof a === 'string' && typeof b === 'string') return a + b;
      if (Array.isArray(a) && Array.isArray(b)) return [...a, ...b];
      if (a instanceof Map && b instanceof Map) {
        const m: JObj = new Map(a);
        for (const [k, v] of b) m.set(k, v);
        return m;
      }
      err(`${typeName(a)} and ${typeName(b)} cannot be added`);
    case '-':
      if (typeof a === 'number' && typeof b === 'number') return a - b;
      if (Array.isArray(a) && Array.isArray(b)) return a.filter((x) => !b.some((y) => compare(x, y) === 0));
      err(`${typeName(a)} and ${typeName(b)} cannot be subtracted`);
    case '*':
      if (typeof a === 'number' && typeof b === 'number') return a * b;
      if (typeof a === 'string' && typeof b === 'number') return b <= 0 ? null : a.repeat(Math.ceil(b));
      if (typeof a === 'number' && typeof b === 'string') return a <= 0 ? null : b.repeat(Math.ceil(a));
      if (a instanceof Map && b instanceof Map) return deepMerge(a, b);
      err(`${typeName(a)} and ${typeName(b)} cannot be multiplied`);
    case '/':
      if (typeof a === 'number' && typeof b === 'number') {
        if (b === 0) err('division by zero');
        return a / b;
      }
      if (typeof a === 'string' && typeof b === 'string') return splitStr(a, b);
      err(`${typeName(a)} and ${typeName(b)} cannot be divided`);
    case '%':
      if (typeof a === 'number' && typeof b === 'number') {
        const bi = Math.trunc(b);
        if (bi === 0) err('division by zero');
        const r = Math.trunc(a) % bi;
        return r === 0 ? 0 : r;
      }
      err(`${typeName(a)} and ${typeName(b)} cannot be divided`);
    default:
      err(`unknown operator ${op}`);
  }
}

// ---------- path get / set / delete ----------
function getPath(v: any, p: any[]): any {
  let cur = v;
  for (const k of p) {
    if (cur === null) return null;
    cur = indexValue(cur, k);
  }
  return cur;
}
function setIn(cur: any, p: any[], i: number, val: any): any {
  if (i === p.length) return val;
  const k = p[i];
  if (typeof k === 'string') {
    if (cur !== null && !(cur instanceof Map)) err(`Cannot index ${typeName(cur)} with string ${escStr(k)}`);
    const m: JObj = cur === null ? new Map() : new Map(cur);
    const child = getKey(m, k);
    m.set(k, setIn(child, p, i + 1, val));
    return m;
  }
  if (typeof k === 'number') {
    if (cur !== null && !Array.isArray(cur)) err(`Cannot index ${typeName(cur)} with number`);
    const arr: any[] = cur === null ? [] : [...cur];
    let idx = Math.floor(k);
    if (idx < 0) {
      idx += arr.length;
      if (idx < 0) err('Out of bounds negative array index');
    }
    while (arr.length < idx) arr.push(null);
    arr[idx] = setIn(idx < arr.length && idx < (cur?.length ?? 0) ? arr[idx] : null, p, i + 1, val);
    return arr;
  }
  err(`Invalid path component ${toJson(k)}`);
}
function setPath(v: any, p: any[], val: any): any {
  return setIn(v, p, 0, val);
}
function delIn(cur: any, p: any[], i: number): any {
  const k = p[i];
  if (i === p.length - 1) {
    if (cur === null) return null;
    if (cur instanceof Map) {
      if (typeof k !== 'string') err(`Cannot delete field at object index of ${typeName(k)}`);
      if (!cur.has(k)) return cur;
      const m: JObj = new Map(cur);
      m.delete(k);
      return m;
    }
    if (Array.isArray(cur)) {
      if (typeof k !== 'number') err(`Cannot delete field at array index of ${typeName(k)}`);
      let idx = Math.floor(k);
      if (idx < 0) idx += cur.length;
      if (idx < 0 || idx >= cur.length) return cur;
      const arr = [...cur];
      arr.splice(idx, 1);
      return arr;
    }
    err(`Cannot delete field at index of ${typeName(cur)}`);
  }
  if (cur === null) return null;
  const child = indexValue(cur, k);
  if (child === null) return cur;
  return setIn(cur, [k], 0, delIn(child, p, i + 1));
}
function delPaths(v: any, paths: any[][]): any {
  const sorted = [...paths].sort((a, b) => compare(b, a));
  let res = v;
  for (const p of sorted) {
    if (p.length === 0) continue;
    res = delIn(res, p, 0);
  }
  return res;
}

// ---------- formats ----------
function fmtApply(name: string, v: any): string {
  switch (name) {
    case 'text': return tostr(v);
    case 'json': return toJson(v);
    case 'csv':
    case 'tsv': {
      if (!Array.isArray(v)) err(`${typeName(v)} cannot be ${name === 'csv' ? 'csv' : 'tsv'}-formatted, only an array can be`);
      const parts = v.map((x: any) => {
        if (x === null) return '';
        if (typeof x === 'boolean') return x ? 'true' : 'false';
        if (typeof x === 'number') return fmtNumber(x);
        if (typeof x === 'string') {
          if (name === 'csv') return '"' + x.replace(/"/g, '""') + '"';
          return x.replace(/\\/g, '\\\\').replace(/\t/g, '\\t').replace(/\n/g, '\\n').replace(/\r/g, '\\r');
        }
        err(`${typeName(x)} is not valid in a csv row`);
      });
      return parts.join(name === 'csv' ? ',' : '\t');
    }
    case 'html':
      return tostr(v).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
        .replace(/'/g, '&#39;').replace(/"/g, '&quot;');
    case 'uri': {
      let out = '';
      for (const b of Buffer.from(tostr(v), 'utf8')) {
        const c = String.fromCharCode(b);
        if (/[A-Za-z0-9\-_.~]/.test(c)) out += c;
        else out += '%' + b.toString(16).toUpperCase().padStart(2, '0');
      }
      return out;
    }
    case 'base64':
      return Buffer.from(tostr(v), 'utf8').toString('base64');
    case 'base64d': {
      const s = tostr(v);
      if (!/^[A-Za-z0-9+/]*={0,2}$/.test(s) || s.replace(/=+$/, '').length % 4 === 1) {
        err(`${toJson(v)} is not valid base64 data`);
      }
      return Buffer.from(s, 'base64').toString('utf8');
    }
    default:
      err(`${name} is not a valid format`);
  }
}

//__PART5__
