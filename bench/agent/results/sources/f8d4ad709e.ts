// Spreadsheet engine: reads a command script on stdin, writes results to stdout. See TASK.md.
import * as fs from 'node:fs';

// ---------- values ----------
type Val =
  | { k: 'n'; v: number }
  | { k: 's'; v: string }
  | { k: 'b'; v: boolean }
  | { k: 'e'; v: string }
  | { k: 'empty' };
interface Rect { c1: number; r1: number; c2: number; r2: number }
type Rng = { k: 'r' } & Rect;
type Res = Val | Rng;
type Node = any;

const EMPTY: Val = { k: 'empty' };
const num = (v: number): Val => ({ k: 'n', v });
const txt = (v: string): Val => ({ k: 's', v });
const bool = (v: boolean): Val => ({ k: 'b', v });
const err = (v: string): Val => ({ k: 'e', v });
const VAL_ERR = err('#VALUE!');

const key = (c: number, r: number): number => c * 1000 + r;
const colOf = (k: number): number => Math.floor(k / 1000);
const rowOf = (k: number): number => k % 1000;
const cellName = (k: number): string => String.fromCharCode(65 + colOf(k)) + rowOf(k);
const sortKeys = (ks: number[]): number[] =>
  ks.sort((a, b) => rowOf(a) - rowOf(b) || colOf(a) - colOf(b));

class CmdError extends Error {}
const fail = (msg: string): never => {
  throw new CmdError(msg);
};

// ---------- state ----------
interface Cell {
  raw: string;
  value: Val;
  formula: boolean;
  ast: Node;
  parseErr: boolean;
  precCells: Set<number>;
  precRects: Rect[];
}
const cells = new Map<number, Cell>();
let evals = 0;
const out: string[] = [];

// ---------- number formatting / grammar ----------
const NUM_FULL = /^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/;
const NUM_TOK = /(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?/y;

function fmtNum(x: number): string {
  if (!isFinite(x)) return '#NUM!';
  if (Math.abs(x) >= 1e21) return BigInt(x).toString();
  let s = x.toFixed(10);
  if (s.includes('.')) s = s.replace(/0+$/, '').replace(/\.$/, '');
  if (s === '-0') s = '0';
  return s;
}

function display(v: Val): string {
  switch (v.k) {
    case 'n': return fmtNum(v.v);
    case 's': return v.v;
    case 'b': return v.v ? 'TRUE' : 'FALSE';
    case 'e': return v.v;
    default: return '';
  }
}

// ---------- references ----------
interface RefInfo { valid: boolean; col: number; row: number; colAbs: boolean; rowAbs: boolean }
function refInfo(w: string): RefInfo {
  const m = /^(\$?)([A-Za-z]+)(\$?)(\d+)$/.exec(w)!;
  const letters = m[2];
  const digits = m[4];
  const valid = letters.length === 1 && /^[1-9]\d{0,2}$/.test(digits);
  return {
    valid,
    col: valid ? letters.toUpperCase().charCodeAt(0) - 65 : -1,
    row: valid ? Number(digits) : 0,
    colAbs: m[1] === '$',
    rowAbs: m[3] === '$',
  };
}

const REF_TOK = /\$?[A-Za-z]+\$?\d+/y;
const ID_TOK = /[A-Za-z_][A-Za-z0-9_.]*/y;
const ID_CH = /[A-Za-z0-9_.]/;
const isDigit = (c: string | undefined): boolean => c !== undefined && c >= '0' && c <= '9';
const isAlpha = (c: string | undefined): boolean => c !== undefined && /^[A-Za-z]$/.test(c);

function tryRef(src: string, i: number): { info: RefInfo; end: number } | null {
  REF_TOK.lastIndex = i;
  const m = REF_TOK.exec(src);
  if (!m) return null;
  const end = REF_TOK.lastIndex;
  if (end < src.length) {
    const ch = src[end];
    if (ID_CH.test(ch) || ch === '(' || ch === '$') return null;
  }
  return { info: refInfo(m[0]), end };
}

// ---------- lexer ----------
interface Tok { t: string; start: number; end: number; v?: any; ref?: RefInfo; a?: RefInfo; b?: RefInfo }

function lex(src: string): Tok[] {
  const toks: Tok[] = [];
  const n = src.length;
  let i = 0;
  while (i < n) {
    const ch = src[i];
    if (ch === ' ' || ch === '\t') { i++; continue; }
    const start = i;
    if (ch === '"') {
      let j = i + 1;
      let s = '';
      for (;;) {
        if (j >= n) throw new Error('unterminated string');
        if (src[j] === '"') {
          if (src[j + 1] === '"') { s += '"'; j += 2; continue; }
          j++;
          break;
        }
        s += src[j++];
      }
      toks.push({ t: 'str', start, end: j, v: s });
      i = j;
      continue;
    }
    if (isDigit(ch) || (ch === '.' && isDigit(src[i + 1]))) {
      NUM_TOK.lastIndex = i;
      NUM_TOK.exec(src);
      const end = NUM_TOK.lastIndex;
      toks.push({ t: 'num', start, end, v: Number(src.slice(i, end)) });
      i = end;
      continue;
    }
    if (ch === '#') {
      if (src.slice(i, i + 5).toUpperCase() === '#REF!') {
        toks.push({ t: 'err', start, end: i + 5 });
        i += 5;
        continue;
      }
      throw new Error('bad token');
    }
    if (ch === '$' || isAlpha(ch)) {
      const r1 = tryRef(src, i);
      if (r1) {
        if (src[r1.end] === ':') {
          const r2 = tryRef(src, r1.end + 1);
          if (r2) {
            toks.push({ t: 'range', start, end: r2.end, a: r1.info, b: r2.info });
            i = r2.end;
            continue;
          }
        }
        toks.push({ t: 'ref', start, end: r1.end, ref: r1.info });
        i = r1.end;
        continue;
      }
      if (ch === '$') throw new Error('bad $');
    }
    if (isAlpha(ch) || ch === '_') {
      ID_TOK.lastIndex = i;
      ID_TOK.exec(src);
      const end = ID_TOK.lastIndex;
      toks.push({ t: 'id', start, end, v: src.slice(i, end) });
      i = end;
      continue;
    }
    const two = src.slice(i, i + 2);
    if (two === '<>' || two === '<=' || two === '>=') {
      toks.push({ t: 'op', start, end: i + 2, v: two });
      i += 2;
      continue;
    }
    if ('+-*/^&=<>(),'.includes(ch)) {
      toks.push({ t: 'op', start, end: i + 1, v: ch });
      i++;
      continue;
    }
    throw new Error('unexpected character');
  }
  return toks;
}

// ---------- parser ----------
const CMP_OPS = ['=', '<>', '<', '<=', '>', '>='];

function refNode(info: RefInfo): Node {
  return { t: 'ref', col: info.col, row: info.row, valid: info.valid };
}

function parse(src: string): Node {
  const toks = lex(src);
  let p = 0;
  const isOp = (v: string): boolean => {
    const t = toks[p];
    return t !== undefined && t.t === 'op' && t.v === v;
  };
  const bad = (): never => { throw new Error('parse error'); };

  function expr(): Node {
    let l = concat();
    for (;;) {
      const t = toks[p];
      if (t && t.t === 'op' && CMP_OPS.includes(t.v)) {
        p++;
        const r = concat();
        l = { t: 'bin', op: t.v, l, r };
      } else return l;
    }
  }
  function concat(): Node {
    let l = add();
    while (isOp('&')) { p++; const r = add(); l = { t: 'bin', op: '&', l, r }; }
    return l;
  }
  function add(): Node {
    let l = mul();
    while (isOp('+') || isOp('-')) {
      const op = toks[p].v; p++;
      const r = mul();
      l = { t: 'bin', op, l, r };
    }
    return l;
  }
  function mul(): Node {
    let l = unary();
    while (isOp('*') || isOp('/')) {
      const op = toks[p].v; p++;
      const r = unary();
      l = { t: 'bin', op, l, r };
    }
    return l;
  }
  function unary(): Node {
    if (isOp('+') || isOp('-')) {
      const op = toks[p].v; p++;
      return { t: 'un', op, x: unary() };
    }
    return pow();
  }
  function pow(): Node {
    const base = primary();
    if (isOp('^')) { p++; const r = powRhs(); return { t: 'bin', op: '^', l: base, r }; }
    return base;
  }
  function powRhs(): Node {
    if (isOp('+') || isOp('-')) {
      const op = toks[p].v; p++;
      return { t: 'un', op, x: powRhs() };
    }
    return pow();
  }
  function primary(): Node {
    const t = toks[p];
    if (!t) return bad();
    p++;
    switch (t.t) {
      case 'num': return { t: 'num', v: t.v };
      case 'str': return { t: 'str', v: t.v };
      case 'err': return { t: 'err' };
      case 'ref': return refNode(t.ref!);
      case 'range': return { t: 'range', a: refNode(t.a!), b: refNode(t.b!) };
      case 'id': {
        if (isOp('(')) {
          p++;
          const args: Node[] = [];
          if (isOp(')')) p++;
          else {
            for (;;) {
              args.push(expr());
              if (isOp(',')) { p++; continue; }
              if (isOp(')')) { p++; break; }
              bad();
            }
          }
          return { t: 'call', name: String(t.v).toUpperCase(), args };
        }
        const u = String(t.v).toUpperCase();
        if (u === 'TRUE') return { t: 'bool', v: true };
        if (u === 'FALSE') return { t: 'bool', v: false };
        return { t: 'name' };
      }
      case 'op':
        if (t.v === '(') {
          const e = expr();
          if (!isOp(')')) bad();
          p++;
          return e;
        }
        return bad();
      default:
        return bad();
    }
  }
  const e = expr();
  if (p !== toks.length) bad();
  return e;
}

function normRect(a: { col: number; row: number }, b: { col: number; row: number }): Rect {
  return {
    c1: Math.min(a.col, b.col),
    r1: Math.min(a.row, b.row),
    c2: Math.max(a.col, b.col),
    r2: Math.max(a.row, b.row),
  };
}

function collectPrec(n: Node, cell: Cell): void {
  if (!n) return;
  switch (n.t) {
    case 'ref':
      if (n.valid) cell.precCells.add(key(n.col, n.row));
      break;
    case 'range':
      if (n.a.valid && n.b.valid) cell.precRects.push(normRect(n.a, n.b));
      break;
    case 'call':
      if (n.name === 'ROW' || n.name === 'COLUMN') break;
      for (const a of n.args) collectPrec(a, cell);
      break;
    case 'un':
      collectPrec(n.x, cell);
      break;
    case 'bin':
      collectPrec(n.l, cell);
      collectPrec(n.r, cell);
      break;
    default:
      break;
  }
}

// ---------- coercion and comparison ----------
function toNum(v: Val): Val {
  switch (v.k) {
    case 'n': return v;
    case 'b': return num(v.v ? 1 : 0);
    case 'empty': return num(0);
    case 's': {
      const t = v.v.trim();
      if (!NUM_FULL.test(t)) return VAL_ERR;
      const x = Number(t);
      return isFinite(x) ? num(x) : VAL_ERR;
    }
    case 'e': return v;
    default: return VAL_ERR;
  }
}

function toBool(v: Val): Val {
  switch (v.k) {
    case 'n': return bool(v.v !== 0);
    case 'b': return v;
    case 'empty': return bool(false);
    case 's': {
      const u = v.v.toUpperCase();
      if (u === 'TRUE') return bool(true);
      if (u === 'FALSE') return bool(false);
      return VAL_ERR;
    }
    case 'e': return v;
    default: return VAL_ERR;
  }
}

function zeroOf(v: Val): Val {
  if (v.k === 'n') return num(0);
  if (v.k === 's') return txt('');
  if (v.k === 'b') return bool(false);
  return EMPTY;
}

function rank(v: Val): number {
  if (v.k === 'n') return 0;
  if (v.k === 's') return 1;
  if (v.k === 'b') return 2;
  return 3;
}

function cmpVals(a: Val, b: Val): number {
  if (a.k === 'empty' && b.k === 'empty') return 0;
  if (a.k === 'empty') a = zeroOf(b);
  else if (b.k === 'empty') b = zeroOf(a);
  const ra = rank(a), rb = rank(b);
  if (ra !== rb) return ra < rb ? -1 : 1;
  if (a.k === 'n' && b.k === 'n') return a.v < b.v ? -1 : a.v > b.v ? 1 : 0;
  if (a.k === 's' && b.k === 's') return Buffer.compare(Buffer.from(a.v, 'utf8'), Buffer.from(b.v, 'utf8'));
  if (a.k === 'b' && b.k === 'b') return (a.v ? 1 : 0) - (b.v ? 1 : 0);
  return 0;
}

function holds(op: string, c: number): boolean {
  switch (op) {
    case '=': return c === 0;
    case '<>': return c !== 0;
    case '<': return c < 0;
    case '<=': return c <= 0;
    case '>': return c > 0;
    case '>=': return c >= 0;
    default: return false;
  }
}

function numRes(x: number): Val {
  return isFinite(x) ? num(x) : err('#NUM!');
}

function arith(op: string, a: number, b: number): Val {
  switch (op) {
    case '+': return numRes(a + b);
    case '-': return numRes(a - b);
    case '*': return numRes(a * b);
    case '/': return b === 0 ? err('#DIV/0!') : numRes(a / b);
    case '^': return numRes(Math.pow(a, b));
    default: return VAL_ERR;
  }
}

// ---------- evaluation ----------
function cellVal(c: number, r: number): Val {
  const cell = cells.get(key(c, r));
  return cell ? cell.value : EMPTY;
}

function ev(n: Node): Res {
  switch (n.t) {
    case 'num': return isFinite(n.v) ? num(n.v) : err('#NUM!');
    case 'str': return txt(n.v);
    case 'bool': return bool(n.v);
    case 'err': return err('#REF!');
    case 'ref': return n.valid ? cellVal(n.col, n.row) : err('#REF!');
    case 'range':
      if (!n.a.valid || !n.b.valid) return err('#REF!');
      return { k: 'r', ...normRect(n.a, n.b) };
    case 'name': return err('#NAME?');
    case 'call': {
      const f = FUNCS.get(n.name);
      if (!f) return err('#NAME?');
      return f(n.args);
    }
    case 'un': {
      const x = toNum(scalar(n.x));
      if (x.k === 'e') return x;
      return n.op === '-' ? numRes(-x.v) : x;
    }
    case 'bin': {
      const op: string = n.op;
      const L = scalar(n.l);
      const R = scalar(n.r);
      if (op === '&') {
        if (L.k === 'e') return L;
        if (R.k === 'e') return R;
        return txt(display(L) + display(R));
      }
      if (CMP_OPS.includes(op)) {
        if (L.k === 'e') return L;
        if (R.k === 'e') return R;
        return bool(holds(op, cmpVals(L, R)));
      }
      const a = toNum(L);
      if (a.k === 'e') return a;
      const b = toNum(R);
      if (b.k === 'e') return b;
      return arith(op, a.v, b.v);
    }
    default:
      return VAL_ERR;
  }
}

// Scalar evaluation: a bare range is #VALUE!.
function scalar(n: Node): Val {
  const r = ev(n);
  if (r.k === 'r') return VAL_ERR;
  return r;
}

function sv(n: Node): Val {
  const v = scalar(n);
  return v.k === 'e' ? v : txt(display(v));
}

interface Item { v: Val; range: boolean }
function items(args: Node[]): Item[] {
  const out: Item[] = [];
  for (const a of args) {
    const r = ev(a);
    if (r.k === 'r') {
      for (let row = r.r1; row <= r.r2; row++)
        for (let c = r.c1; c <= r.c2; c++) out.push({ v: cellVal(c, row), range: true });
    } else out.push({ v: r, range: false });
  }
  return out;
}

// Numeric items: errors and coercion failures come back as `e`.
function nums(args: Node[]): { e?: Val; nums: number[] } {
  const res: number[] = [];
  for (const it of items(args)) {
    const v = it.v;
    if (v.k === 'e') return { e: v, nums: res };
    if (it.range) {
      if (v.k === 'n') res.push(v.v);
    } else {
      const c = toNum(v);
      if (c.k === 'e') return { e: c, nums: res };
      res.push(c.v);
    }
  }
  return { nums: res };
}

function evalFormula(cell: Cell): Val {
  if (cell.parseErr) return err('#PARSE!');
  const r = ev(cell.ast);
  if (r.k === 'r') return VAL_ERR;
  if (r.k === 'empty') return num(0);
  return r;
}

// ---------- functions ----------
type Fn = (a: Node[]) => Res;
const FUNCS = new Map<string, Fn>();
const F = (name: string, f: Fn): void => { FUNCS.set(name, f); };

F('SUM', (a) => {
  if (!a.length) return VAL_ERR;
  const r = nums(a);
  if (r.e) return r.e;
  let s = 0;
  for (const x of r.nums) s += x;
  return numRes(s);
});

F('AVERAGE', (a) => {
  if (!a.length) return VAL_ERR;
  const r = nums(a);
  if (r.e) return r.e;
  if (!r.nums.length) return err('#DIV/0!');
  let s = 0;
  for (const x of r.nums) s += x;
  return numRes(s / r.nums.length);
});

F('MIN', (a) => {
  if (!a.length) return VAL_ERR;
  const r = nums(a);
  if (r.e) return r.e;
  if (!r.nums.length) return num(0);
  let m = Infinity;
  for (const x of r.nums) m = Math.min(m, x);
  return num(m);
});

F('MAX', (a) => {
  if (!a.length) return VAL_ERR;
  const r = nums(a);
  if (r.e) return r.e;
  if (!r.nums.length) return num(0);
  let m = -Infinity;
  for (const x of r.nums) m = Math.max(m, x);
  return num(m);
});

F('PRODUCT', (a) => {
  if (!a.length) return VAL_ERR;
  const r = nums(a);
  if (r.e) return r.e;
  if (!r.nums.length) return num(0);
  let p = 1;
  for (const x of r.nums) p *= x;
  return numRes(p);
});

F('MEDIAN', (a) => {
  if (!a.length) return VAL_ERR;
  const r = nums(a);
  if (r.e) return r.e;
  const s = r.nums.slice().sort((x, y) => x - y);
  const len = s.length;
  if (!len) return err('#NUM!');
  const mid = len >> 1;
  if (len % 2 === 1) return numRes(s[mid]);
  return numRes((s[mid - 1] + s[mid]) / 2);
});

F('COUNT', (a) => {
  if (!a.length) return VAL_ERR;
  let c = 0;
  for (const it of items(a)) if (it.v.k === 'n') c++;
  return num(c);
});

F('COUNTA', (a) => {
  if (!a.length) return VAL_ERR;
  let c = 0;
  for (const it of items(a)) if (it.v.k !== 'empty') c++;
  return num(c);
});

F('IF', (a) => {
  if (a.length < 2 || a.length > 3) return VAL_ERR;
  const c = toBool(scalar(a[0]));
  if (c.k === 'e') return c;
  if (c.v) return scalar(a[1]);
  return a.length === 3 ? scalar(a[2]) : bool(false);
});

F('IFERROR', (a) => {
  if (a.length !== 2) return VAL_ERR;
  const x = scalar(a[0]);
  return x.k === 'e' ? scalar(a[1]) : x;
});

F('CHOOSE', (a) => {
  if (a.length < 2) return VAL_ERR;
  const i = toNum(scalar(a[0]));
  if (i.k === 'e') return i;
  const idx = Math.floor(i.v);
  if (idx < 1 || idx > a.length - 1) return VAL_ERR;
  return scalar(a[idx]);
});

function andOr(a: Node[], isAnd: boolean): Res {
  if (!a.length) return VAL_ERR;
  let res = isAnd;
  let cnt = 0;
  for (const it of items(a)) {
    const v = it.v;
    if (v.k === 'e') return v;
    if (it.range && (v.k === 's' || v.k === 'empty')) continue;
    const b = toBool(v);
    if (b.k === 'e') return b;
    cnt++;
    res = isAnd ? res && b.v : res || b.v;
  }
  return cnt ? bool(res) : VAL_ERR;
}
F('AND', (a) => andOr(a, true));
F('OR', (a) => andOr(a, false));

F('NOT', (a) => {
  if (a.length !== 1) return VAL_ERR;
  const b = toBool(scalar(a[0]));
  return b.k === 'e' ? b : bool(!b.v);
});

function unaryNum(f: (x: number) => Val): Fn {
  return (a) => {
    if (a.length !== 1) return VAL_ERR;
    const x = toNum(scalar(a[0]));
    if (x.k === 'e') return x;
    return f(x.v);
  };
}
F('ABS', unaryNum((x) => numRes(Math.abs(x))));
F('INT', unaryNum((x) => numRes(Math.floor(x))));
F('SQRT', unaryNum((x) => (x < 0 ? err('#NUM!') : numRes(Math.sqrt(x)))));

function binNum(f: (x: number, y: number) => Val): Fn {
  return (a) => {
    if (a.length !== 2) return VAL_ERR;
    const x = toNum(scalar(a[0]));
    if (x.k === 'e') return x;
    const y = toNum(scalar(a[1]));
    if (y.k === 'e') return y;
    return f(x.v, y.v);
  };
}
F('POW', binNum((x, y) => arith('^', x, y)));
F('MOD', binNum((x, y) => {
  if (y === 0) return err('#DIV/0!');
  return numRes(x - y * Math.floor(x / y));
}));

F('ROUND', (a) => {
  if (a.length < 1 || a.length > 2) return VAL_ERR;
  const x = toNum(scalar(a[0]));
  if (x.k === 'e') return x;
  let d = 0;
  if (a.length === 2) {
    const dv = toNum(scalar(a[1]));
    if (dv.k === 'e') return dv;
    d = Math.trunc(dv.v);
  }
  if (Math.abs(d) > 15) return err('#NUM!');
  const p = Math.pow(10, d);
  const y = x.v * p;
  const r = Math.sign(y) * Math.round(Math.abs(y));
  return numRes(r / p);
});

F('LEN', (a) => {
  if (a.length !== 1) return VAL_ERR;
  const s = sv(a[0]);
  return s.k === 'e' ? s : num(Array.from(s.v).length);
});

F('UPPER', (a) => {
  if (a.length !== 1) return VAL_ERR;
  const s = sv(a[0]);
  return s.k === 'e' ? s : txt(s.v.replace(/[a-z]+/g, (m) => m.toUpperCase()));
});

F('LOWER', (a) => {
  if (a.length !== 1) return VAL_ERR;
  const s = sv(a[0]);
  return s.k === 'e' ? s : txt(s.v.replace(/[A-Z]+/g, (m) => m.toLowerCase()));
});

F('TRIM', (a) => {
  if (a.length !== 1) return VAL_ERR;
  const s = sv(a[0]);
  return s.k === 'e' ? s : txt(s.v.trim().replace(/\s+/g, ' '));
});

function textPart(a: Node[], left: boolean): Res {
  if (a.length < 1 || a.length > 2) return VAL_ERR;
  const s = sv(a[0]);
  if (s.k === 'e') return s;
  let n = 1;
  if (a.length === 2) {
    const nv = toNum(scalar(a[1]));
    if (nv.k === 'e') return nv;
    n = Math.floor(nv.v);
  }
  if (n < 0) return VAL_ERR;
  const ch = Array.from(s.v);
  if (left) return txt(ch.slice(0, n).join(''));
  return txt(ch.slice(Math.max(0, ch.length - n)).join(''));
}
F('LEFT', (a) => textPart(a, true));
F('RIGHT', (a) => textPart(a, false));

F('MID', (a) => {
  if (a.length !== 3) return VAL_ERR;
  const s = sv(a[0]);
  if (s.k === 'e') return s;
  const st = toNum(scalar(a[1]));
  if (st.k === 'e') return st;
  const ln = toNum(scalar(a[2]));
  if (ln.k === 'e') return ln;
  const start = Math.floor(st.v);
  const len = Math.floor(ln.v);
  if (start < 1 || len < 0) return VAL_ERR;
  return txt(Array.from(s.v).slice(start - 1, start - 1 + len).join(''));
});

F('CONCAT', (a) => {
  if (!a.length) return VAL_ERR;
  let s = '';
  for (const it of items(a)) {
    if (it.v.k === 'e') return it.v;
    s += display(it.v);
  }
  return txt(s);
});

F('SUBSTITUTE', (a) => {
  if (a.length !== 3) return VAL_ERR;
  const s = sv(a[0]);
  if (s.k === 'e') return s;
  const o = sv(a[1]);
  if (o.k === 'e') return o;
  const nw = sv(a[2]);
  if (nw.k === 'e') return nw;
  if (o.v === '') return s;
  return txt(s.v.split(o.v).join(nw.v));
});

F('VALUE', (a) => {
  if (a.length !== 1) return VAL_ERR;
  return toNum(scalar(a[0]));
});

F('ISERROR', (a) => (a.length === 1 ? bool(scalar(a[0]).k === 'e') : VAL_ERR));
F('ISBLANK', (a) => (a.length === 1 ? bool(scalar(a[0]).k === 'empty') : VAL_ERR));
F('ISNUMBER', (a) => (a.length === 1 ? bool(scalar(a[0]).k === 'n') : VAL_ERR));
F('ISTEXT', (a) => (a.length === 1 ? bool(scalar(a[0]).k === 's') : VAL_ERR));

function rowCol(a: Node[], isRow: boolean): Val {
  if (a.length !== 1) return VAL_ERR;
  const n = a[0];
  if (n.t === 'ref') {
    if (!n.valid) return err('#REF!');
    return num(isRow ? n.row : n.col + 1);
  }
  if (n.t === 'range') {
    if (!n.a.valid || !n.b.valid) return err('#REF!');
    const R = normRect(n.a, n.b);
    return num(isRow ? R.r1 : R.c1 + 1);
  }
  return VAL_ERR;
}
F('ROW', (a) => rowCol(a, true));
F('COLUMN', (a) => rowCol(a, false));

F('INDEX', (a) => {
  if (a.length !== 2 && a.length !== 3) return VAL_ERR;
  if (a[0].t !== 'range') return VAL_ERR;
  if (!a[0].a.valid || !a[0].b.valid) return err('#REF!');
  const R = normRect(a[0].a, a[0].b);
  const rows = R.r2 - R.r1 + 1;
  const cols = R.c2 - R.c1 + 1;
  const rv = toNum(scalar(a[1]));
  if (rv.k === 'e') return rv;
  let ri: number;
  let ci: number;
  if (a.length === 3) {
    const cv = toNum(scalar(a[2]));
    if (cv.k === 'e') return cv;
    ri = Math.floor(rv.v);
    ci = Math.floor(cv.v);
  } else if (rows === 1) {
    ri = 1;
    ci = Math.floor(rv.v);
  } else {
    ri = Math.floor(rv.v);
    ci = 1;
  }
  if (ri < 1 || ri > rows || ci < 1 || ci > cols) return err('#REF!');
  return cellVal(R.c1 + ci - 1, R.r1 + ri - 1);
});

F('COUNTIF', (a) => {
  if (a.length !== 2) return VAL_ERR;
  if (a[0].t !== 'range') return VAL_ERR;
  if (!a[0].a.valid || !a[0].b.valid) return err('#REF!');
  const R = normRect(a[0].a, a[0].b);
  const crit = scalar(a[1]);
  if (crit.k === 'e') return crit;
  let op = '=';
  let operand: Val = crit;
  if (crit.k === 's') {
    let s = crit.v;
    for (const o of ['>=', '<=', '<>', '>', '<', '=']) {
      if (s.startsWith(o)) {
        op = o;
        s = s.slice(o.length);
        break;
      }
    }
    operand = NUM_FULL.test(s) && isFinite(Number(s)) ? num(Number(s)) : txt(s);
  }
  let count = 0;
  for (let r = R.r1; r <= R.r2; r++) {
    for (let c = R.c1; c <= R.c2; c++) {
      const v = cellVal(c, r);
      if (v.k === operand.k) {
        if (holds(op, cmpVals(v, operand))) count++;
      } else if (op === '<>' && v.k !== 'empty') {
        count++;
      }
    }
  }
  return num(count);
});

// ---------- dependency graph and recalculation ----------
interface Index {
  single: Map<number, number[]>;
  rects: { c1: number; r1: number; c2: number; r2: number; f: number }[];
}

function buildIndex(): Index {
  const single = new Map<number, number[]>();
  const rects: Index['rects'] = [];
  for (const [k, c] of cells) {
    if (!c.formula) continue;
    for (const p of c.precCells) {
      let list = single.get(p);
      if (!list) {
        list = [];
        single.set(p, list);
      }
      list.push(k);
    }
    for (const r of c.precRects) rects.push({ ...r, f: k });
  }
  return { single, rects };
}

// Formula cells that directly depend on cell k.
function dependentsOf(idx: Index, k: number): number[] {
  const res = [...(idx.single.get(k) ?? [])];
  const c = colOf(k);
  const r = rowOf(k);
  for (const rc of idx.rects) {
    if (c >= rc.c1 && c <= rc.c2 && r >= rc.r1 && r <= rc.r2) res.push(rc.f);
  }
  return res;
}

function evalAffected(A: Set<number>, idx: Index): number {
  const list = [...A];
  // Edges point from a formula to its dependents, restricted to the affected set.
  const adj = new Map<number, number[]>();
  for (const p of list) {
    const ds = new Set<number>();
    for (const d of dependentsOf(idx, p)) if (A.has(d)) ds.add(d);
    adj.set(p, [...ds]);
  }
  // Tarjan's SCC. Emission order is dependents-first, so reverse it.
  const index = new Map<number, number>();
  const low = new Map<number, number>();
  const onStack = new Set<number>();
  const stack: number[] = [];
  let counter = 0;
  const sccs: number[][] = [];
  const strong = (v: number): void => {
    index.set(v, counter);
    low.set(v, counter);
    counter++;
    stack.push(v);
    onStack.add(v);
    for (const w of adj.get(v)!) {
      if (!index.has(w)) {
        strong(w);
        low.set(v, Math.min(low.get(v)!, low.get(w)!));
      } else if (onStack.has(w)) {
        low.set(v, Math.min(low.get(v)!, index.get(w)!));
      }
    }
    if (low.get(v) === index.get(v)) {
      const comp: number[] = [];
      let w: number;
      do {
        w = stack.pop()!;
        onStack.delete(w);
        comp.push(w);
      } while (w !== v);
      sccs.push(comp);
    }
  };
  for (const v of list) if (!index.has(v)) strong(v);
  sccs.reverse();
  for (const comp of sccs) {
    const cyclic = comp.length > 1 || adj.get(comp[0])!.includes(comp[0]);
    for (const v of comp) {
      const cell = cells.get(v)!;
      cell.value = cyclic ? err('#CYCLE!') : evalFormula(cell);
    }
  }
  return list.length;
}

function recalc(changed: number[]): number {
  const idx = buildIndex();
  const A = new Set<number>();
  const queue: number[] = [];
  const seen = new Set<number>();
  for (const k of changed) {
    if (seen.has(k)) continue;
    seen.add(k);
    queue.push(k);
    const c = cells.get(k);
    if (c && c.formula) A.add(k);
  }
  for (let qi = 0; qi < queue.length; qi++) {
    for (const d of dependentsOf(idx, queue[qi])) {
      if (!A.has(d)) {
        A.add(d);
        queue.push(d);
      }
    }
  }
  const n = evalAffected(A, idx);
  evals += n;
  return n;
}

// ---------- cell assignment ----------
function assign(k: number, raw: string): void {
  const t = raw.trim();
  if (t === '') {
    cells.delete(k);
    return;
  }
  const cell: Cell = {
    raw: t,
    value: EMPTY,
    formula: false,
    ast: null,
    parseErr: false,
    precCells: new Set<number>(),
    precRects: [],
  };
  if (t[0] === '=') {
    cell.formula = true;
    try {
      cell.ast = parse(t.slice(1));
      collectPrec(cell.ast, cell);
    } catch {
      cell.parseErr = true;
      cell.ast = null;
      cell.precCells.clear();
      cell.precRects = [];
    }
  } else if (t[0] === "'") {
    cell.value = txt(t.slice(1));
  } else if (NUM_FULL.test(t) && isFinite(Number(t))) {
    cell.value = num(Number(t));
  } else if (/^true$/i.test(t)) {
    cell.value = bool(true);
  } else if (/^false$/i.test(t)) {
    cell.value = bool(false);
  } else {
    cell.value = txt(t);
  }
  cells.set(k, cell);
}

// ---------- formula shifting (copy) ----------
function fmtRef(c: number, r: number, cAbs: boolean, rAbs: boolean): string {
  return (cAbs ? '$' : '') + String.fromCharCode(65 + c) + (rAbs ? '$' : '') + r;
}

function shiftFormula(src: string, dc: number, dr: number): string {
  let toks: Tok[];
  try {
    toks = lex(src);
  } catch {
    return src;
  }
  let res = '';
  let pos = 0;
  for (const t of toks) {
    if (t.t !== 'ref' && t.t !== 'range') continue;
    res += src.slice(pos, t.start);
    const text = src.slice(t.start, t.end);
    if (t.t === 'ref') {
      const info = t.ref!;
      if (!info.valid) res += text;
      else {
        const c = info.colAbs ? info.col : info.col + dc;
        const r = info.rowAbs ? info.row : info.row + dr;
        res += c < 0 || c > 25 || r < 1 || r > 999 ? '#REF!' : fmtRef(c, r, info.colAbs, info.rowAbs);
      }
    } else {
      const a = t.a!;
      const b = t.b!;
      if (!a.valid || !b.valid) res += text;
      else {
        const ca = a.colAbs ? a.col : a.col + dc;
        const ra = a.rowAbs ? a.row : a.row + dr;
        const cb = b.colAbs ? b.col : b.col + dc;
        const rb = b.rowAbs ? b.row : b.row + dr;
        const ok = [ca, cb].every((c) => c >= 0 && c <= 25) && [ra, rb].every((r) => r >= 1 && r <= 999);
        res += ok
          ? fmtRef(ca, ra, a.colAbs, a.rowAbs) + ':' + fmtRef(cb, rb, b.colAbs, b.rowAbs)
          : '#REF!';
      }
    }
    pos = t.end;
  }
  res += src.slice(pos);
  return res;
}

// ---------- commands ----------
function parseCellOpt(tok: string): number | null {
  const m = /^([A-Za-z])([1-9]\d{0,2})$/.exec(tok);
  if (!m) return null;
  return key(m[1].toUpperCase().charCodeAt(0) - 65, Number(m[2]));
}

function parseCell(tok: string): number {
  const k = parseCellOpt(tok);
  if (k === null) fail(`bad cell reference '${tok}'`);
  return k as number;
}

function parseRange(tok: string): Rect {
  const parts = tok.split(':');
  if (parts.length > 2) fail(`bad range '${tok}'`);
  const ks = parts.map(parseCellOpt);
  if (ks.some((k) => k === null)) fail(`bad range '${tok}'`);
  const a = ks[0] as number;
  const b = (ks[1] ?? ks[0]) as number;
  return normRect({ col: colOf(a), row: rowOf(a) }, { col: colOf(b), row: rowOf(b) });
}

function defaultRect(): Rect | null {
  if (cells.size === 0) return null;
  let maxC = 0;
  let maxR = 1;
  for (const k of cells.keys()) {
    maxC = Math.max(maxC, colOf(k));
    maxR = Math.max(maxR, rowOf(k));
  }
  return { c1: 0, r1: 1, c2: maxC, r2: maxR };
}

function csvField(f: string): string {
  if (/[,"\r\n]/.test(f) || f.startsWith(' ') || f.endsWith(' ')) return '"' + f.replace(/"/g, '""') + '"';
  return f;
}

function parseCSV(text: string): string[][] {
  const recs: string[][] = [];
  let rec: string[] = [];
  let field = '';
  let inQ = false;
  let has = false;
  const n = text.length;
  let i = 0;
  while (i < n) {
    const ch = text[i];
    if (inQ) {
      if (ch === '"') {
        if (text[i + 1] === '"') { field += '"'; i += 2; continue; }
        inQ = false;
        i++;
        continue;
      }
      field += ch;
      i++;
      continue;
    }
    if (ch === '"') { inQ = true; has = true; i++; continue; }
    if (ch === ',') { rec.push(field); field = ''; has = true; i++; continue; }
    if (ch === '\n') {
      if (has) { rec.push(field); recs.push(rec); }
      rec = [];
      field = '';
      has = false;
      i++;
      continue;
    }
    if (ch === '\r') { i++; continue; }
    field += ch;
    has = true;
    i++;
  }
  if (has) { rec.push(field); recs.push(rec); }
  return recs;
}

function doImport(rest: string, block: string[]): void {
  const args = rest === '' ? [] : rest.split(/\s+/);
  if (args.length !== 1) fail('usage: import CELL');
  const k = parseCell(args[0]);
  const recs = parseCSV(block.join('\n'));
  const R = recs.length;
  const C = recs.reduce((m, r) => Math.max(m, r.length), 0);
  const c0 = colOf(k);
  const r0 = rowOf(k);
  if (R > 0 && (c0 + C - 1 > 25 || r0 + R - 1 > 999)) fail('import out of range');
  const changed: number[] = [];
  recs.forEach((rec, i) =>
    rec.forEach((f, j) => {
      const kk = key(c0 + j, r0 + i);
      assign(kk, f);
      changed.push(kk);
    }),
  );
  out.push(`imported ${R} rows, ${C} columns; recalc ${recalc(changed)}`);
}

function execute(cmd: string, rest: string): void {
  const args = rest === '' ? [] : rest.split(/\s+/);
  switch (cmd) {
    case 'set': {
      if (rest === '') fail('usage: set CELL VALUE');
      const k = parseCell(args[0]);
      const value = rest.slice(args[0].length).trim();
      assign(k, value);
      out.push(`recalc ${recalc([k])}`);
      return;
    }
    case 'clear': {
      if (args.length !== 1) fail('usage: clear CELL');
      const k = parseCell(args[0]);
      assign(k, '');
      out.push(`recalc ${recalc([k])}`);
      return;
    }
    case 'get': {
      if (args.length !== 1) fail('usage: get CELL');
      const k = parseCell(args[0]);
      const cell = cells.get(k);
      out.push(cell ? display(cell.value) : '(empty)');
      return;
    }
    case 'show': {
      if (args.length !== 1) fail('usage: show CELL');
      const k = parseCell(args[0]);
      const cell = cells.get(k);
      const name = cellName(k);
      if (!cell) out.push(`${name}: (empty)`);
      else if (cell.formula) out.push(`${name}: ${cell.raw} => ${display(cell.value)}`);
      else out.push(`${name}: ${cell.raw}`);
      return;
    }
    case 'precedents': {
      if (args.length !== 1) fail('usage: precedents CELL');
      const k = parseCell(args[0]);
      const cell = cells.get(k);
      const set = new Set<number>();
      if (cell && cell.formula && !cell.parseErr) {
        for (const p of cell.precCells) set.add(p);
        for (const r of cell.precRects)
          for (let c = r.c1; c <= r.c2; c++)
            for (let row = r.r1; row <= r.r2; row++) set.add(key(c, row));
      }
      out.push(set.size ? sortKeys([...set]).map(cellName).join(' ') : '(none)');
      return;
    }
    case 'dependents': {
      if (args.length !== 1) fail('usage: dependents CELL');
      const k = parseCell(args[0]);
      const idx = buildIndex();
      const seen = new Set<number>();
      const q = [k];
      for (let qi = 0; qi < q.length; qi++) {
        for (const d of dependentsOf(idx, q[qi])) {
          if (!seen.has(d)) {
            seen.add(d);
            q.push(d);
          }
        }
      }
      out.push(seen.size ? sortKeys([...seen]).map(cellName).join(' ') : '(none)');
      return;
    }
    case 'print': {
      if (args.length > 1 || args[0] === 'formulas') fail('usage: print [RANGE]');
      const R = args.length ? parseRange(args[0]) : defaultRect();
      if (!R) {
        out.push('(empty sheet)');
        return;
      }
      for (let r = R.r1; r <= R.r2; r++) {
        const fields: string[] = [];
        for (let c = R.c1; c <= R.c2; c++) fields.push(display(cellVal(c, r)));
        out.push(fields.join(' | '));
      }
      return;
    }
    case 'export': {
      let mode = 'values';
      let modeSet = false;
      let rangeTok: string | null = null;
      for (const t of args) {
        if (t === 'formulas' || t === 'values') {
          if (modeSet) fail('usage: export [formulas] [RANGE]');
          mode = t;
          modeSet = true;
        } else {
          if (rangeTok !== null) fail('usage: export [formulas] [RANGE]');
          rangeTok = t;
        }
      }
      const R = rangeTok !== null ? parseRange(rangeTok) : defaultRect();
      if (!R) {
        out.push('(empty sheet)');
        return;
      }
      for (let r = R.r1; r <= R.r2; r++) {
        const fields: string[] = [];
        for (let c = R.c1; c <= R.c2; c++) {
          if (mode === 'formulas') {
            const cell = cells.get(key(c, r));
            fields.push(cell ? cell.raw : '');
          } else {
            fields.push(display(cellVal(c, r)));
          }
        }
        out.push(fields.map(csvField).join(','));
      }
      return;
    }
    case 'copy': {
      if (args.length !== 2) fail('usage: copy SRC DST');
      const sk = parseCell(args[0]);
      const D = parseRange(args[1]);
      const sc = cells.get(sk);
      const changed: number[] = [];
      for (let r = D.r1; r <= D.r2; r++) {
        for (let c = D.c1; c <= D.c2; c++) {
          const dk = key(c, r);
          let raw = '';
          if (sc) {
            raw = sc.formula
              ? '=' + shiftFormula(sc.raw.slice(1), c - colOf(sk), r - rowOf(sk))
              : sc.raw;
          }
          assign(dk, raw);
          changed.push(dk);
        }
      }
      out.push(`recalc ${recalc(changed)}`);
      return;
    }
    case 'stats': {
      let formulas = 0;
      for (const c of cells.values()) if (c.formula) formulas++;
      out.push(`cells ${cells.size} formulas ${formulas} evals ${evals}`);
      return;
    }
    default:
      fail(`unknown command '${cmd}'`);
  }
}

// ---------- main loop ----------
const input = fs.readFileSync(0, 'utf8');
const lines = input.split('\n').map((l) => (l.endsWith('\r') ? l.slice(0, -1) : l));
let li = 0;
while (li < lines.length) {
  const raw = lines[li++];
  const line = raw.trim();
  if (line === '' || line.startsWith('#')) continue;
  out.push('> ' + raw.trimEnd());
  const m = /^(\S+)\s*([\s\S]*)$/.exec(line)!;
  const cmd = m[1];
  const rest = m[2];
  try {
    if (cmd === 'import') {
      const block: string[] = [];
      while (li < lines.length && lines[li] !== '.') block.push(lines[li++]);
      if (li < lines.length) li++;
      doImport(rest, block);
    } else {
      execute(cmd, rest);
    }
  } catch (e) {
    out.push('error: ' + (e as Error).message);
  }
}

process.stdout.write(out.length ? out.join('\n') + '\n' : '');
