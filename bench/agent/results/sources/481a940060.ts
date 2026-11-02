// SQL engine: reads a SQL script on stdin and writes results to stdout. See TASK.md.
import { readFileSync } from 'node:fs';

// Runtime values. TEXT is a "byte string": every char code is a byte (input is read as latin1),
// so LENGTH, comparisons, LIKE and LOWER/UPPER all work bytewise.
type Val = null | boolean | bigint | string;
// AST nodes are plain objects; `any` keeps the code compact.
type Node = any;

class SqlError {
  msg: string;
  constructor(msg: string) {
    this.msg = msg;
  }
}

function fail(msg: string): never {
  throw new SqlError(msg);
}

// ---------- Lexer ----------

interface Tok {
  t: string; // kw | id | int | str | op | err | eof
  v: string;
  n: bigint;
}

const EOF_TOK: Tok = { t: 'eof', v: '', n: 0n };
const MAX_INT = 9223372036854775807n;
const KEYWORDS = new Set([
  'SELECT', 'FROM', 'WHERE', 'GROUP', 'BY', 'HAVING', 'ORDER', 'LIMIT', 'OFFSET', 'JOIN', 'LEFT', 'INNER',
  'ON', 'AS', 'AND', 'OR', 'NOT', 'NULL', 'IS', 'LIKE', 'IN', 'BETWEEN', 'INSERT', 'INTO', 'VALUES',
  'UPDATE', 'SET', 'DELETE', 'CREATE', 'TABLE', 'DROP', 'PRIMARY', 'KEY', 'DISTINCT', 'ASC', 'DESC',
]);

function isDigit(c: string): boolean {
  return c >= '0' && c <= '9';
}
function isIdStart(c: string): boolean {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c === '_';
}
function isIdChar(c: string): boolean {
  return isIdStart(c) || isDigit(c);
}

// Lexes the whole input and splits it into statements at `;` (outside strings and comments).
// Lexical errors become 'err' tokens, so they only affect the statement that contains them.
function lexAll(src: string): Tok[][] {
  const stmts: Tok[][] = [];
  let cur: Tok[] = [];
  const n = src.length;
  let i = 0;
  const push = (t: string, v: string, num: bigint) => {
    cur.push({ t, v, n: num });
  };
  while (i < n) {
    const c = src[i];
    if (c === ' ' || c === '\t' || c === '\r' || c === '\n') {
      i++;
      continue;
    }
    if (c === '-' && src[i + 1] === '-') {
      while (i < n && src[i] !== '\n') i++;
      continue;
    }
    if (c === ';') {
      stmts.push(cur);
      cur = [];
      i++;
      continue;
    }
    if (c === "'") {
      let j = i + 1;
      let s = '';
      let closed = false;
      while (j < n) {
        const d = src[j];
        if (d === "'") {
          if (src[j + 1] === "'") {
            s += "'";
            j += 2;
            continue;
          }
          closed = true;
          j++;
          break;
        }
        s += d;
        j++;
      }
      if (closed) push('str', s, 0n);
      else push('err', '', 0n);
      i = j;
      continue;
    }
    if (isDigit(c)) {
      let j = i;
      while (j < n && isDigit(src[j])) j++;
      const val = BigInt(src.slice(i, j));
      if (val > MAX_INT) push('err', '', 0n);
      else push('int', src.slice(i, j), val);
      i = j;
      continue;
    }
    if (isIdStart(c)) {
      let j = i;
      while (j < n && isIdChar(src[j])) j++;
      const w = src.slice(i, j);
      const up = w.toUpperCase();
      if (KEYWORDS.has(up)) push('kw', up, 0n);
      else push('id', w, 0n);
      i = j;
      continue;
    }
    const two = src.slice(i, i + 2);
    if (two === '<>' || two === '!=' || two === '<=' || two === '>=' || two === '||') {
      push('op', two, 0n);
      i += 2;
      continue;
    }
    if ('=<>+-*/%(),.'.includes(c)) {
      push('op', c, 0n);
      i++;
      continue;
    }
    push('err', c, 0n);
    i++;
  }
  stmts.push(cur);
  return stmts;
}

// ---------- Parser ----------

class Parser {
  toks: Tok[];
  pos: number;

  constructor(toks: Tok[]) {
    this.toks = toks;
    this.pos = 0;
  }

  peek(o: number = 0): Tok {
    const i = this.pos + o;
    return i < this.toks.length ? this.toks[i] : EOF_TOK;
  }
  adv(): Tok {
    const t = this.peek();
    this.pos++;
    return t;
  }
  kw(v: string, o: number = 0): boolean {
    const t = this.peek(o);
    return t.t === 'kw' && t.v === v;
  }
  op(v: string, o: number = 0): boolean {
    const t = this.peek(o);
    return t.t === 'op' && t.v === v;
  }
  acceptKw(v: string): boolean {
    if (this.kw(v)) {
      this.pos++;
      return true;
    }
    return false;
  }
  acceptOp(v: string): boolean {
    if (this.op(v)) {
      this.pos++;
      return true;
    }
    return false;
  }
  expectKw(v: string): void {
    if (!this.acceptKw(v)) fail('syntax error');
  }
  expectOp(v: string): void {
    if (!this.acceptOp(v)) fail('syntax error');
  }
  ident(): string {
    const t = this.peek();
    if (t.t === 'id') {
      this.pos++;
      return t.v;
    }
    return fail('syntax error');
  }
  intLit(): bigint {
    const t = this.peek();
    if (t.t === 'int') {
      this.pos++;
      return t.n;
    }
    return fail('syntax error');
  }
  end(): void {
    if (this.pos !== this.toks.length) fail('syntax error');
  }

  parseStatement(): Node {
    const t = this.peek();
    if (t.t !== 'kw') fail('syntax error');
    let s: Node;
    switch (t.v) {
      case 'SELECT':
        s = this.select();
        break;
      case 'CREATE':
        s = this.create();
        break;
      case 'DROP':
        s = this.drop();
        break;
      case 'INSERT':
        s = this.insert();
        break;
      case 'UPDATE':
        s = this.update();
        break;
      case 'DELETE':
        s = this.del();
        break;
      default:
        return fail('syntax error');
    }
    this.end();
    return s;
  }

  create(): Node {
    this.expectKw('CREATE');
    this.expectKw('TABLE');
    const name = this.ident();
    this.expectOp('(');
    const cols = [this.coldef()];
    while (this.acceptOp(',')) cols.push(this.coldef());
    this.expectOp(')');
    return { type: 'create', name, cols };
  }

  coldef(): Node {
    const name = this.ident();
    const ty = this.ident().toUpperCase();
    if (ty !== 'INT' && ty !== 'TEXT') fail('syntax error');
    let pk = false;
    let notnull = false;
    for (;;) {
      if (this.acceptKw('PRIMARY')) {
        this.expectKw('KEY');
        pk = true;
      } else if (this.acceptKw('NOT')) {
        this.expectKw('NULL');
        notnull = true;
      } else break;
    }
    return { name, type: ty, pk, notnull };
  }

  drop(): Node {
    this.expectKw('DROP');
    this.expectKw('TABLE');
    return { type: 'drop', name: this.ident() };
  }

  insert(): Node {
    this.expectKw('INSERT');
    this.expectKw('INTO');
    const name = this.ident();
    let cols: string[] | null = null;
    if (this.acceptOp('(')) {
      cols = [this.ident()];
      while (this.acceptOp(',')) cols.push(this.ident());
      this.expectOp(')');
    }
    this.expectKw('VALUES');
    const rows = [this.valueRow()];
    while (this.acceptOp(',')) rows.push(this.valueRow());
    return { type: 'insert', name, cols, rows };
  }

  valueRow(): Node[] {
    this.expectOp('(');
    const r = [this.expr()];
    while (this.acceptOp(',')) r.push(this.expr());
    this.expectOp(')');
    return r;
  }

  update(): Node {
    this.expectKw('UPDATE');
    const name = this.ident();
    this.expectKw('SET');
    const sets: { name: string; e: Node }[] = [];
    do {
      const col = this.ident();
      this.expectOp('=');
      sets.push({ name: col, e: this.expr() });
    } while (this.acceptOp(','));
    const where = this.acceptKw('WHERE') ? this.expr() : null;
    return { type: 'update', name, sets, where };
  }

  del(): Node {
    this.expectKw('DELETE');
    this.expectKw('FROM');
    const name = this.ident();
    const where = this.acceptKw('WHERE') ? this.expr() : null;
    return { type: 'delete', name, where };
  }

  select(): Node {
    this.expectKw('SELECT');
    const distinct = this.acceptKw('DISTINCT');
    const items = [this.item()];
    while (this.acceptOp(',')) items.push(this.item());
    let from: Node = null;
    const joins: Node[] = [];
    if (this.acceptKw('FROM')) {
      from = this.tref();
      for (;;) {
        let kind = 'INNER';
        if (this.acceptKw('LEFT')) kind = 'LEFT';
        else if (this.acceptKw('INNER')) kind = 'INNER';
        else if (!this.kw('JOIN')) break;
        this.expectKw('JOIN');
        const t = this.tref();
        this.expectKw('ON');
        const on = this.expr();
        joins.push({ kind, tref: t, on });
      }
    }
    const where = this.acceptKw('WHERE') ? this.expr() : null;
    const groupBy: Node[] = [];
    if (this.acceptKw('GROUP')) {
      this.expectKw('BY');
      groupBy.push(this.colref());
      while (this.acceptOp(',')) groupBy.push(this.colref());
    }
    const having = this.acceptKw('HAVING') ? this.expr() : null;
    const orderBy: Node[] = [];
    if (this.acceptKw('ORDER')) {
      this.expectKw('BY');
      do {
        orderBy.push(this.orderItem());
      } while (this.acceptOp(','));
    }
    let limit: bigint | null = null;
    let offset: bigint | null = null;
    if (this.acceptKw('LIMIT')) {
      limit = this.intLit();
      if (this.acceptKw('OFFSET')) offset = this.intLit();
    }
    return { type: 'select', distinct, items, from, joins, where, groupBy, having, orderBy, limit, offset };
  }

  item(): Node {
    if (this.acceptOp('*')) return { k: 'star' };
    if (this.peek().t === 'id' && this.op('.', 1) && this.op('*', 2)) {
      const table = this.ident();
      this.pos += 2;
      return { k: 'tstar', table };
    }
    const e = this.expr();
    const alias = this.acceptKw('AS') ? this.ident() : null;
    return { k: 'expr', e, alias };
  }

  tref(): Node {
    const table = this.ident();
    let alias = table;
    if (this.acceptKw('AS')) alias = this.ident();
    else if (this.peek().t === 'id') alias = this.adv().v;
    return { table, alias };
  }

  colref(): Node {
    const name = this.ident();
    if (this.acceptOp('.')) return { k: 'col', table: name, name: this.ident(), slot: -1 };
    return { k: 'col', table: null, name, slot: -1 };
  }

  orderItem(): Node {
    const t = this.peek();
    let pos: number | null = null;
    let e: Node = null;
    if (
      t.t === 'int' &&
      (this.op(',', 1) || this.kw('ASC', 1) || this.kw('DESC', 1) || this.kw('LIMIT', 1) || this.peek(1).t === 'eof')
    ) {
      pos = Number(t.n);
      this.pos++;
    } else {
      e = this.expr();
    }
    let desc = false;
    if (this.acceptKw('DESC')) desc = true;
    else this.acceptKw('ASC');
    return { pos, e, desc };
  }

  // Expressions, lowest precedence first.
  expr(): Node {
    return this.or();
  }

  or(): Node {
    let l = this.and();
    while (this.acceptKw('OR')) {
      const r = this.and();
      l = { k: 'bin', op: 'OR', l, r };
    }
    return l;
  }

  and(): Node {
    let l = this.not();
    while (this.acceptKw('AND')) {
      const r = this.not();
      l = { k: 'bin', op: 'AND', l, r };
    }
    return l;
  }

  not(): Node {
    if (this.acceptKw('NOT')) return { k: 'not', e: this.not() };
    return this.cmp();
  }

  cmp(): Node {
    const l = this.add();
    const t = this.peek();
    if (t.t === 'op' && ['=', '<>', '!=', '<', '<=', '>', '>='].includes(t.v)) {
      this.pos++;
      const r = this.add();
      return { k: 'bin', op: t.v === '!=' ? '<>' : t.v, l, r };
    }
    if (this.acceptKw('IS')) {
      const neg = this.acceptKw('NOT');
      this.expectKw('NULL');
      return { k: 'isnull', e: l, neg };
    }
    let neg = false;
    if (this.kw('NOT') && (this.kw('LIKE', 1) || this.kw('IN', 1) || this.kw('BETWEEN', 1))) {
      this.pos++;
      neg = true;
    }
    if (this.acceptKw('LIKE')) {
      const p = this.add();
      return { k: 'like', e: l, p, neg };
    }
    if (this.acceptKw('IN')) {
      this.expectOp('(');
      const list = [this.expr()];
      while (this.acceptOp(',')) list.push(this.expr());
      this.expectOp(')');
      return { k: 'in', e: l, list, neg };
    }
    if (this.acceptKw('BETWEEN')) {
      const lo = this.add();
      this.expectKw('AND');
      const hi = this.add();
      return { k: 'between', e: l, lo, hi, neg };
    }
    return l;
  }

  add(): Node {
    let l = this.mul();
    for (;;) {
      const t = this.peek();
      if (t.t === 'op' && (t.v === '+' || t.v === '-' || t.v === '||')) {
        this.pos++;
        const r = this.mul();
        l = { k: 'bin', op: t.v, l, r };
      } else return l;
    }
  }

  mul(): Node {
    let l = this.unary();
    for (;;) {
      const t = this.peek();
      if (t.t === 'op' && (t.v === '*' || t.v === '/' || t.v === '%')) {
        this.pos++;
        const r = this.unary();
        l = { k: 'bin', op: t.v, l, r };
      } else return l;
    }
  }

  unary(): Node {
    if (this.acceptOp('-')) return { k: 'neg', e: this.unary() };
    return this.primary();
  }

  primary(): Node {
    const t = this.peek();
    if (t.t === 'int') {
      this.pos++;
      return { k: 'lit', v: t.n };
    }
    if (t.t === 'str') {
      this.pos++;
      return { k: 'lit', v: t.v };
    }
    if (t.t === 'kw' && t.v === 'NULL') {
      this.pos++;
      return { k: 'lit', v: null };
    }
    if (this.op('(')) {
      this.pos++;
      const e = this.expr();
      this.expectOp(')');
      return e;
    }
    if (t.t === 'id') {
      if (this.op('(', 1)) {
        const name = t.v.toUpperCase();
        this.pos += 2;
        let distinct = false;
        let star = false;
        const args: Node[] = [];
        if (this.acceptKw('DISTINCT')) distinct = true;
        if (this.acceptOp('*')) star = true;
        else if (!this.op(')')) {
          args.push(this.expr());
          while (this.acceptOp(',')) args.push(this.expr());
        }
        this.expectOp(')');
        return { k: 'call', name, distinct, star, args };
      }
      this.pos++;
      if (this.acceptOp('.')) return { k: 'col', table: t.v, name: this.ident(), slot: -1 };
      return { k: 'col', table: null, name: t.v, slot: -1 };
    }
    return fail('syntax error');
  }
}

// ---------- Schema and storage ----------

interface Col {
  name: string;
  type: string; // 'INT' | 'TEXT'
  notnull: boolean;
  pk: boolean;
}

interface Table {
  name: string;
  cols: Col[];
  rows: Val[][];
}

const tables = new Map<string, Table>();

const FUNCS = new Map<string, { min: number; max: number; agg: boolean }>([
  ['UPPER', { min: 1, max: 1, agg: false }],
  ['LOWER', { min: 1, max: 1, agg: false }],
  ['LENGTH', { min: 1, max: 1, agg: false }],
  ['ABS', { min: 1, max: 1, agg: false }],
  ['SUBSTR', { min: 3, max: 3, agg: false }],
  ['COALESCE', { min: 1, max: Infinity, agg: false }],
  ['COUNT', { min: 1, max: 1, agg: true }],
  ['SUM', { min: 1, max: 1, agg: true }],
  ['MIN', { min: 1, max: 1, agg: true }],
  ['MAX', { min: 1, max: 1, agg: true }],
]);

// ---------- Value helpers ----------

function fmt(v: Val): string {
  if (v === null) return 'NULL';
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  return String(v);
}

function keyOf(v: Val): string {
  if (v === null) return 'N';
  if (typeof v === 'boolean') return v ? 'T' : 'F';
  if (typeof v === 'bigint') return 'I' + v.toString() + ';';
  return 'S' + v.length + ':' + v;
}

// Compares two non-NULL INT values or two non-NULL TEXT values; anything else is a type error.
function cmpSame(l: Val, r: Val): number {
  if (typeof l === 'bigint' && typeof r === 'bigint') return l < r ? -1 : l > r ? 1 : 0;
  if (typeof l === 'string' && typeof r === 'string') return l < r ? -1 : l > r ? 1 : 0;
  return fail('type error');
}

function rank(v: Val): number {
  if (v === null) return 0;
  if (typeof v === 'boolean') return 1;
  if (typeof v === 'bigint') return 2;
  return 3;
}

// Sort order for ORDER BY keys: NULL < (boolean) < INT < TEXT.
function sortCmp(a: Val, b: Val): number {
  const ra = rank(a);
  const rb = rank(b);
  if (ra !== rb) return ra - rb;
  if (a === null || b === null) return 0;
  if (typeof a === 'boolean' && typeof b === 'boolean') return (a ? 1 : 0) - (b ? 1 : 0);
  if (typeof a === 'bigint' && typeof b === 'bigint') return a < b ? -1 : a > b ? 1 : 0;
  if (typeof a === 'string' && typeof b === 'string') return a < b ? -1 : a > b ? 1 : 0;
  return 0;
}

function condTrue(v: Val): boolean {
  if (v === true) return true;
  if (v === false || v === null) return false;
  return fail('type error');
}

function chkBool(v: Val): void {
  if (v !== null && typeof v !== 'boolean') fail('type error');
}

function and3(a: Val, b: Val): Val {
  if (a === false || b === false) return false;
  if (a === true && b === true) return true;
  return null;
}

function or3(a: Val, b: Val): Val {
  if (a === true || b === true) return true;
  if (a === false && b === false) return false;
  return null;
}

// LIKE pattern to a whole-string, byte-level regular expression.
function likeRe(p: string): RegExp {
  let re = '^';
  for (const ch of p) {
    if (ch === '%') re += '[\\s\\S]*';
    else if (ch === '_') re += '[\\s\\S]';
    else re += ch.replace(/[.*+?^${}()|[\]\\\/-]/g, '\\$&');
  }
  return new RegExp(re + '$');
}

function kids(e: Node): Node[] {
  const out: Node[] = [];
  for (const x of [e.e, e.l, e.r, e.p, e.lo, e.hi]) if (x) out.push(x);
  if (e.list) out.push(...e.list);
  if (e.args) out.push(...e.args);
  return out;
}

function hasAgg(e: Node): boolean {
  if (e.k === 'call' && FUNCS.get(e.name)?.agg) return true;
  return kids(e).some(hasAgg);
}

// ---------- Name resolution ----------

interface ScopeCol {
  alias: string;
  name: string;
  slot: number;
}

interface RCtx {
  scope: ScopeCol[];
  allowAgg: boolean; // aggregates may appear here
  inAgg: boolean; // inside an aggregate's argument
  aggregated: boolean; // query is grouped: bare columns must be GROUP BY columns
  groupSlots: Set<number> | null;
}

function plainCx(scope: ScopeCol[]): RCtx {
  return { scope, allowAgg: false, inAgg: false, aggregated: false, groupSlots: null };
}

function lookupCol(e: Node, scope: ScopeCol[]): number {
  if (e.table !== null) {
    const m = scope.find((c) => c.alias === e.table && c.name === e.name);
    if (!m) fail(`no such column: ${e.table}.${e.name}`);
    return m.slot;
  }
  const m = scope.filter((c) => c.name === e.name);
  if (m.length === 0) fail(`no such column: ${e.name}`);
  if (m.length > 1) fail(`ambiguous column: ${e.name}`);
  return m[0].slot;
}

function resolveCall(e: Node, cx: RCtx): void {
  const info = FUNCS.get(e.name);
  if (!info) fail(`no such function: ${e.name}`);
  const n = e.args.length;
  const bad = (): never => fail(`wrong number of arguments to ${e.name}`);
  if (e.distinct && (e.star || n !== 1)) bad();
  if (e.star) {
    if (e.name !== 'COUNT') bad();
  } else if (n < info.min || n > info.max) bad();
  if (info.agg) {
    if (!cx.allowAgg) fail('misuse of aggregate');
    const sub = { ...cx, allowAgg: false, inAgg: true };
    for (const a of e.args) resolveExpr(a, sub);
  } else {
    for (const a of e.args) resolveExpr(a, cx);
  }
}

function resolveExpr(e: Node, cx: RCtx): void {
  if (e.k === 'col') {
    e.slot = lookupCol(e, cx.scope);
    if (cx.aggregated && !cx.inAgg && !(cx.groupSlots as Set<number>).has(e.slot)) {
      fail(`column ${e.table !== null ? e.table + '.' : ''}${e.name} must appear in GROUP BY`);
    }
    return;
  }
  if (e.k === 'call') {
    resolveCall(e, cx);
    return;
  }
  for (const k of kids(e)) resolveExpr(k, cx);
}

// ---------- Expression evaluation ----------

interface Group {
  rows: Val[][];
  cache: Map<Node, Val>;
  rep: Val[]; // representative row for group columns
}

function str(v: Val): string {
  if (typeof v !== 'string') fail('type error');
  return v;
}

function int(v: Val): bigint {
  if (typeof v !== 'bigint') fail('type error');
  return v;
}

function scalarFn(name: string, vals: Val[]): Val {
  if (name === 'COALESCE') {
    for (const v of vals) if (v !== null) return v;
    return null;
  }
  if (vals.some((v) => v === null)) return null;
  switch (name) {
    case 'UPPER':
      return str(vals[0]).replace(/[a-z]/g, (ch) => ch.toUpperCase());
    case 'LOWER':
      return str(vals[0]).replace(/[A-Z]/g, (ch) => ch.toLowerCase());
    case 'LENGTH':
      return BigInt(str(vals[0]).length);
    case 'ABS': {
      const v = int(vals[0]);
      return v < 0n ? -v : v;
    }
    case 'SUBSTR': {
      const t = str(vals[0]);
      const start = int(vals[1]);
      const len = int(vals[2]);
      if (len <= 0n) return '';
      const size = BigInt(t.length);
      const from = start < 1n ? 1n : start;
      const endExcl = start + len > size + 1n ? size + 1n : start + len;
      if (from >= endExcl) return '';
      return t.slice(Number(from) - 1, Number(endExcl) - 1);
    }
  }
  return fail(`no such function: ${name}`);
}

function aggValue(e: Node, g: Group): Val {
  const cached = g.cache.get(e);
  if (cached !== undefined) return cached;
  let res: Val;
  if (e.star) {
    res = BigInt(g.rows.length);
  } else {
    let vals: Val[] = g.rows.map((r) => ev(e.args[0], r, null));
    vals = vals.filter((v) => v !== null);
    if (e.distinct) {
      const seen = new Set<string>();
      vals = vals.filter((v) => {
        const k = keyOf(v);
        if (seen.has(k)) return false;
        seen.add(k);
        return true;
      });
    }
    switch (e.name) {
      case 'COUNT':
        res = BigInt(vals.length);
        break;
      case 'SUM': {
        if (vals.length === 0) {
          res = null;
          break;
        }
        let s = 0n;
        for (const v of vals) s += int(v);
        res = s;
        break;
      }
      default: {
        // MIN / MAX: INT or TEXT only, all values of one type.
        if (vals.length === 0) {
          res = null;
          break;
        }
        const isInt = typeof vals[0] === 'bigint';
        for (const v of vals) {
          if (isInt ? typeof v !== 'bigint' : typeof v !== 'string') fail('type error');
        }
        let best = vals[0];
        for (const v of vals) {
          const c = cmpSame(v, best);
          if (e.name === 'MIN' ? c < 0 : c > 0) best = v;
        }
        res = best;
      }
    }
  }
  g.cache.set(e, res);
  return res;
}

function binop(e: Node, row: Val[], g: Group | null): Val {
  const op: string = e.op;
  if (op === 'AND') {
    const l = ev(e.l, row, g);
    if (l === false) return false;
    chkBool(l);
    const r = ev(e.r, row, g);
    chkBool(r);
    return and3(l, r);
  }
  if (op === 'OR') {
    const l = ev(e.l, row, g);
    if (l === true) return true;
    chkBool(l);
    const r = ev(e.r, row, g);
    chkBool(r);
    return or3(l, r);
  }
  const l = ev(e.l, row, g);
  const r = ev(e.r, row, g);
  if (l === null || r === null) return null;
  switch (op) {
    case '+':
    case '-':
    case '*':
    case '/':
    case '%': {
      if (typeof l !== 'bigint' || typeof r !== 'bigint') fail('type error');
      if (op === '+') return l + r;
      if (op === '-') return l - r;
      if (op === '*') return l * r;
      if (r === 0n) fail('division by zero');
      return op === '/' ? l / r : l % r;
    }
    case '||':
      if (typeof l !== 'string' || typeof r !== 'string') fail('type error');
      return l + r;
    default: {
      const c = cmpSame(l, r);
      switch (op) {
        case '=':
          return c === 0;
        case '<>':
          return c !== 0;
        case '<':
          return c < 0;
        case '<=':
          return c <= 0;
        case '>':
          return c > 0;
        default:
          return c >= 0;
      }
    }
  }
}

function ev(e: Node, row: Val[], g: Group | null): Val {
  switch (e.k) {
    case 'lit':
      return e.v;
    case 'col':
      return row[e.slot];
    case 'neg': {
      const v = ev(e.e, row, g);
      if (v === null) return null;
      return -int(v);
    }
    case 'not': {
      const v = ev(e.e, row, g);
      if (v === null) return null;
      if (typeof v !== 'boolean') fail('type error');
      return !v;
    }
    case 'isnull': {
      const v = ev(e.e, row, g);
      return (v === null) !== (e.neg === true);
    }
    case 'like': {
      const v = ev(e.e, row, g);
      const p = ev(e.p, row, g);
      if (v === null || p === null) return null;
      if (typeof v !== 'string' || typeof p !== 'string') fail('type error');
      const m = likeRe(p).test(v);
      return e.neg ? !m : m;
    }
    case 'in': {
      const x = ev(e.e, row, g);
      const vals: Val[] = e.list.map((a: Node) => ev(a, row, g));
      let res: Val;
      if (x === null) {
        res = null;
      } else {
        let found = false;
        let sawNull = false;
        for (const v of vals) {
          if (v === null) sawNull = true;
          else if (cmpSame(x, v) === 0) found = true;
        }
        res = found ? true : sawNull ? null : false;
      }
      if (e.neg && res !== null) res = !res;
      return res;
    }
    case 'between': {
      const x = ev(e.e, row, g);
      const lo = ev(e.lo, row, g);
      const hi = ev(e.hi, row, g);
      const a: Val = x === null || lo === null ? null : cmpSame(x, lo) >= 0;
      let res: Val;
      if (a === false) {
        res = false;
      } else {
        const b: Val = x === null || hi === null ? null : cmpSame(x, hi) <= 0;
        res = and3(a, b);
      }
      if (e.neg && res !== null) res = !res;
      return res;
    }
    case 'call': {
      const info = FUNCS.get(e.name) as { agg: boolean };
      if (info.agg) {
        if (!g) fail('misuse of aggregate');
        return aggValue(e, g);
      }
      const vals = e.args.map((a: Node) => ev(a, row, g));
      return scalarFn(e.name, vals);
    }
    case 'bin':
      return binop(e, row, g);
  }
  return fail('syntax error');
}

// ---------- Statements ----------

function plainScope(t: Table): ScopeCol[] {
  return t.cols.map((c, i) => ({ alias: t.name, name: c.name, slot: i }));
}

// Per-row constraints in column declaration order.
function checkRow(t: Table, row: Val[]): void {
  t.cols.forEach((c, i) => {
    const v = row[i];
    if (v === null) {
      if (c.notnull) fail(`NOT NULL constraint failed: ${c.name}`);
    } else if (c.type === 'INT' ? typeof v !== 'bigint' : typeof v !== 'string') {
      fail(`type mismatch in column ${c.name}`);
    }
  });
}

function checkPK(t: Table, rows: Val[][]): void {
  const pi = t.cols.findIndex((c) => c.pk);
  if (pi < 0) return;
  const seen = new Set<string>();
  for (const r of rows) {
    const k = keyOf(r[pi]);
    if (seen.has(k)) fail(`duplicate primary key: ${fmt(r[pi])}`);
    seen.add(k);
  }
}

function getTable(name: string): Table {
  const t = tables.get(name);
  if (!t) fail(`no such table: ${name}`);
  return t;
}

function createTable(s: Node): string[] {
  if (tables.has(s.name)) fail(`table ${s.name} already exists`);
  const seen = new Set<string>();
  for (const c of s.cols) {
    if (seen.has(c.name)) fail(`duplicate column: ${c.name}`);
    seen.add(c.name);
  }
  if (s.cols.filter((c: Node) => c.pk).length > 1) fail('multiple primary keys');
  tables.set(s.name, {
    name: s.name,
    cols: s.cols.map((c: Node) => ({ name: c.name, type: c.type, notnull: c.notnull || c.pk, pk: c.pk })),
    rows: [],
  });
  return ['ok'];
}

function insertRows(s: Node): string[] {
  const t = getTable(s.name);
  let colIdx: number[] = t.cols.map((_, i) => i);
  if (s.cols !== null) {
    colIdx = [];
    for (const name of s.cols as string[]) {
      const idx = t.cols.findIndex((c) => c.name === name);
      if (idx < 0) fail(`no such column: ${name}`);
      if (colIdx.includes(idx)) fail(`duplicate column: ${name}`);
      colIdx.push(idx);
    }
  }
  const newRows: Val[][] = [];
  for (const row of s.rows as Node[][]) {
    if (row.length !== colIdx.length) fail('wrong number of values');
    const vals: Val[] = row.map((e: Node) => {
      resolveExpr(e, plainCx([]));
      return ev(e, [], null);
    });
    const full: Val[] = t.cols.map(() => null);
    colIdx.forEach((ci, k) => {
      full[ci] = vals[k];
    });
    checkRow(t, full);
    newRows.push(full);
  }
  const all = t.rows.concat(newRows);
  checkPK(t, all);
  t.rows = all;
  return [`inserted ${newRows.length}`];
}

function updateRows(s: Node): string[] {
  const t = getTable(s.name);
  const idxs: number[] = s.sets.map((a: Node) => {
    const i = t.cols.findIndex((c) => c.name === a.name);
    if (i < 0) fail(`no such column: ${a.name}`);
    return i;
  });
  const scope = plainScope(t);
  for (const a of s.sets) resolveExpr(a.e, plainCx(scope));
  if (s.where) resolveExpr(s.where, plainCx(scope));
  let count = 0;
  const newRows: Val[][] = [];
  for (const row of t.rows) {
    if (s.where && !condTrue(ev(s.where, row, null))) {
      newRows.push(row);
      continue;
    }
    count++;
    const vals: Val[] = s.sets.map((a: Node) => ev(a.e, row, null));
    const nr = row.slice();
    idxs.forEach((ci, k) => {
      nr[ci] = vals[k];
    });
    checkRow(t, nr);
    newRows.push(nr);
  }
  checkPK(t, newRows);
  t.rows = newRows;
  return [`updated ${count}`];
}

function deleteRows(s: Node): string[] {
  const t = getTable(s.name);
  if (s.where) resolveExpr(s.where, plainCx(plainScope(t)));
  let n = 0;
  const kept: Val[][] = [];
  for (const row of t.rows) {
    if (!s.where || condTrue(ev(s.where, row, null))) n++;
    else kept.push(row);
  }
  t.rows = kept;
  return [`deleted ${n}`];
}

function runSelect(s: Node): string[] {
  // Step 1: tables exist, aliases are unique; build the visible columns (FROM order).
  const trefs: Node[] = s.from ? [s.from, ...s.joins.map((j: Node) => j.tref)] : [];
  const srcs: { table: Table; alias: string; offset: number }[] = [];
  const scope: ScopeCol[] = [];
  const joinScopeLen: number[] = [];
  let width = 0;
  trefs.forEach((tr, idx) => {
    const t = getTable(tr.table);
    if (srcs.some((x) => x.alias === tr.alias)) fail(`duplicate alias: ${tr.alias}`);
    srcs.push({ table: t, alias: tr.alias, offset: width });
    t.cols.forEach((c, i) => scope.push({ alias: tr.alias, name: c.name, slot: width + i }));
    width += t.cols.length;
    if (idx > 0) joinScopeLen.push(scope.length);
  });

  // Step 2: name resolution, in the specified order.
  s.joins.forEach((j: Node, k: number) => {
    resolveExpr(j.on, { ...plainCx(scope.slice(0, joinScopeLen[k])), allowAgg: false });
  });
  for (const it of s.items) {
    if (it.k === 'tstar' && !srcs.some((x) => x.alias === it.table)) fail(`no such table: ${it.table}`);
  }
  const gslots: number[] = s.groupBy.map((c: Node) => lookupCol(c, scope));
  const groupSlots = new Set<number>(gslots);
  if (s.where) resolveExpr(s.where, plainCx(scope));

  const aggregated: boolean =
    s.groupBy.length > 0 ||
    s.having !== null ||
    s.items.some((it: Node) => it.k === 'expr' && hasAgg(it.e)) ||
    s.orderBy.some((o: Node) => o.e !== null && hasAgg(o.e));
  const cx: RCtx = { scope, allowAgg: true, inAgg: false, aggregated, groupSlots };

  const outs: { name: string; e: Node }[] = [];
  for (const it of s.items) {
    if (it.k === 'expr') {
      resolveExpr(it.e, cx);
      const name = it.alias !== null ? it.alias : it.e.k === 'col' ? it.e.name : '?column?';
      outs.push({ name, e: it.e });
    } else {
      for (const c of scope) {
        if (it.k === 'tstar' && c.alias !== it.table) continue;
        if (aggregated && !groupSlots.has(c.slot)) fail(`column ${c.name} must appear in GROUP BY`);
        outs.push({ name: c.name, e: { k: 'col', table: c.alias, name: c.name, slot: c.slot } });
      }
    }
  }
  if (s.having) resolveExpr(s.having, cx);

  const keys: { idx: number | null; e: Node; desc: boolean }[] = [];
  for (const o of s.orderBy) {
    if (o.pos !== null) {
      if (o.pos < 1 || o.pos > outs.length) fail('bad ORDER BY position');
      keys.push({ idx: o.pos - 1, e: null, desc: o.desc });
    } else if (o.e.k === 'col' && o.e.table === null && outs.some((x) => x.name === o.e.name)) {
      const idx = outs.findIndex((x) => x.name === o.e.name);
      keys.push({ idx, e: null, desc: o.desc });
    } else {
      resolveExpr(o.e, cx);
      keys.push({ idx: null, e: o.e, desc: o.desc });
    }
  }

  // Step 3: build rows (nested-loop joins).
  let rows: Val[][];
  if (!s.from) {
    rows = [[]];
  } else {
    let cur: Val[][] = srcs[0].table.rows;
    s.joins.forEach((j: Node, k: number) => {
      const inner = srcs[k + 1].table;
      const next: Val[][] = [];
      for (const o of cur) {
        let matched = false;
        for (const r of inner.rows) {
          const comb = o.concat(r);
          if (condTrue(ev(j.on, comb, null))) {
            matched = true;
            next.push(comb);
          }
        }
        if (!matched && j.kind === 'LEFT') next.push(o.concat(inner.cols.map((): Val => null)));
      }
      cur = next;
    });
    rows = cur;
  }

  // Step 4: WHERE.
  if (s.where) rows = rows.filter((r) => condTrue(ev(s.where, r, null)));

  // Steps 5-6: grouping and projection; each record keeps output values and sort keys.
  const recs: { vals: Val[]; keys: Val[] }[] = [];
  const emit = (row: Val[], g: Group | null): void => {
    const vals = outs.map((o) => ev(o.e, row, g));
    const ks = keys.map((k) => (k.idx !== null ? vals[k.idx] : ev(k.e, row, g)));
    recs.push({ vals, keys: ks });
  };
  if (!aggregated) {
    for (const r of rows) emit(r, null);
  } else {
    const nullRow: Val[] = Array(width).fill(null);
    let groups: Group[];
    if (s.groupBy.length === 0) {
      groups = [{ rows, cache: new Map(), rep: rows.length > 0 ? rows[0] : nullRow }];
    } else {
      const map = new Map<string, Group>();
      for (const r of rows) {
        const gk = gslots.map((sl) => keyOf(r[sl])).join('');
        const existing = map.get(gk);
        if (existing) existing.rows.push(r);
        else map.set(gk, { rows: [r], cache: new Map(), rep: r });
      }
      groups = [...map.values()];
    }
    for (const g of groups) {
      if (s.having && !condTrue(ev(s.having, g.rep, g))) continue;
      emit(g.rep, g);
    }
  }

  // Step 7: DISTINCT, then ORDER BY, then OFFSET / LIMIT.
  let out = recs;
  if (s.distinct) {
    const seen = new Set<string>();
    out = out.filter((r) => {
      const k = r.vals.map((v) => keyOf(v)).join('');
      if (seen.has(k)) return false;
      seen.add(k);
      return true;
    });
  }
  if (keys.length > 0) {
    out = out.slice().sort((a, b) => {
      for (let i = 0; i < keys.length; i++) {
        let c = sortCmp(a.keys[i], b.keys[i]);
        if (keys[i].desc) c = -c;
        if (c !== 0) return c;
      }
      return 0;
    });
  }
  const off = s.offset !== null ? Number(s.offset) : 0;
  const lim = s.limit !== null ? Number(s.limit) : Infinity;
  out = out.slice(off, off + lim);

  const lines = [outs.map((o) => o.name).join('|')];
  for (const r of out) lines.push(r.vals.map((v) => fmt(v)).join('|'));
  lines.push(`(${out.length} rows)`);
  return lines;
}

function execStatement(s: Node): string[] {
  switch (s.type) {
    case 'select':
      return runSelect(s);
    case 'create':
      return createTable(s);
    case 'drop':
      getTable(s.name);
      tables.delete(s.name);
      return ['ok'];
    case 'insert':
      return insertRows(s);
    case 'update':
      return updateRows(s);
    case 'delete':
      return deleteRows(s);
  }
  return fail('syntax error');
}

// ---------- Main ----------

const src = readFileSync(0).toString('latin1');
const outLines: string[] = [];
for (const toks of lexAll(src)) {
  if (toks.length === 0) continue;
  try {
    const stmt = new Parser(toks).parseStatement();
    for (const line of execStatement(stmt)) outLines.push(line + '\n');
  } catch (err) {
    if (err instanceof SqlError) outLines.push('error: ' + err.msg + '\n');
    else outLines.push('error: ' + String(err) + '\n');
  }
}
process.stdout.write(Buffer.from(outLines.join(''), 'latin1'));
