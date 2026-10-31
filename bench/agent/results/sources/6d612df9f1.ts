// Read stdin, write stdout. See TASK.md.
// A Scheme-like interpreter. The evaluator runs in a worker thread with a large
// stack so that the 10000-deep recursion limit can be reached without JS overflow.
import { Worker, isMainThread, workerData, parentPort } from 'node:worker_threads';
import * as fs from 'node:fs';

// ---------------------------------------------------------------- data

class Sym {
  name: string;
  constructor(name: string) { this.name = name; }
}

class Pair {
  car: Value;
  cdr: Value;
  constructor(car: Value, cdr: Value) { this.car = car; this.cdr = cdr; }
}

class Nil {}
class Void {}
const NIL = new Nil();
const VOID = new Void();

class Frame {
  vars: Map<string, Value>;
  parent: Frame | null;
  constructor(parent: Frame | null) { this.vars = new Map(); this.parent = parent; }
}

class Closure {
  params: string[];
  rest: string | null;
  body: Value[];
  env: Frame;
  name: string | null;
  constructor(params: string[], rest: string | null, body: Value[], env: Frame, name: string | null) {
    this.params = params; this.rest = rest; this.body = body; this.env = env; this.name = name;
  }
}

class Builtin {
  name: string;
  min: number;
  max: number;
  fn: (args: Value[]) => Value;
  constructor(name: string, min: number, max: number, fn: (args: Value[]) => Value) {
    this.name = name; this.min = min; this.max = max; this.fn = fn;
  }
}

type Value = bigint | boolean | string | Sym | Pair | Nil | Void | Closure | Builtin;

// Runtime or syntax error. Not an Error subclass: cheap to throw inside try.
class SErr {
  msg: string;
  syntax: boolean;
  constructor(msg: string, syntax: boolean) { this.msg = msg; this.syntax = syntax; }
}

function rt(msg: string): SErr { return new SErr(msg, false); }
function syn(msg: string): SErr { return new SErr('syntax error: ' + msg, true); }
function bad(kw: string): SErr { return syn(`bad form: ${kw}`); }

const MAXI = 9223372036854775807n;
const MINI = -9223372036854775808n;
function ck(n: bigint): bigint {
  if (n > MAXI || n < MINI) throw rt('integer overflow');
  return n;
}

function fromArray(items: Value[], tail: Value = NIL): Value {
  let r: Value = tail;
  for (let i = items.length - 1; i >= 0; i--) r = new Pair(items[i], r);
  return r;
}

// Array of elements of a proper list, or null.
function toArray(v: Value): Value[] | null {
  const out: Value[] = [];
  let cur = v;
  while (cur instanceof Pair) { out.push(cur.car); cur = cur.cdr; }
  return cur === NIL ? out : null;
}

// ---------------------------------------------------------------- reader

const EOF_SENTINEL = null;
const DELIM = new Set([' ', '\t', '\n', '\r', '(', ')', '"', ';']);

class Reader {
  s: string;
  n: number;
  i: number;
  constructor(s: string) { this.s = s; this.n = s.length; this.i = 0; }

  skip(): void {
    while (this.i < this.n) {
      const c = this.s[this.i];
      if (c === ' ' || c === '\t' || c === '\n' || c === '\r') this.i++;
      else if (c === ';') {
        while (this.i < this.n && this.s[this.i] !== '\n') this.i++;
      } else break;
    }
  }

  // Next top-level datum, or null at end of input.
  top(): Value | null {
    this.skip();
    if (this.i >= this.n) return EOF_SENTINEL;
    return this.datum();
  }

  datum(): Value {
    this.skip();
    if (this.i >= this.n) throw syn('unexpected end of input');
    const c = this.s[this.i];
    if (c === '(') { this.i++; return this.list(); }
    if (c === ')') throw syn('unexpected )');
    if (c === "'") {
      this.i++;
      const d = this.datum();
      return new Pair(new Sym('quote'), new Pair(d, NIL));
    }
    if (c === '"') { this.i++; return this.str(); }
    const start = this.i;
    while (this.i < this.n && !DELIM.has(this.s[this.i])) this.i++;
    return atom(this.s.slice(start, this.i));
  }

  isDelimAt(k: number): boolean {
    return k >= this.n || DELIM.has(this.s[k]);
  }

  list(): Value {
    const items: Value[] = [];
    let tail: Value = NIL;
    for (;;) {
      this.skip();
      if (this.i >= this.n) throw syn('unexpected end of input');
      const c = this.s[this.i];
      if (c === ')') { this.i++; break; }
      if (c === '.' && this.isDelimAt(this.i + 1)) {
        this.i++;
        if (items.length === 0) throw syn('bad dotted list');
        this.skip();
        if (this.i >= this.n) throw syn('unexpected end of input');
        if (this.s[this.i] === ')') throw syn('bad dotted list');
        tail = this.datum();
        this.skip();
        if (this.i >= this.n) throw syn('unexpected end of input');
        if (this.s[this.i] !== ')') throw syn('bad dotted list');
        this.i++;
        break;
      }
      items.push(this.datum());
    }
    return fromArray(items, tail);
  }

  str(): string {
    let out = '';
    for (;;) {
      if (this.i >= this.n) throw syn('unterminated string');
      const c = this.s[this.i++];
      if (c === '"') break;
      if (c === '\\') {
        if (this.i >= this.n) throw syn('unterminated string');
        const e = this.s[this.i++];
        if (e === 'n') out += '\n';
        else if (e === 't') out += '\t';
        else if (e === '\\') out += '\\';
        else if (e === '"') out += '"';
        else throw syn('bad escape');
      } else {
        out += c;
      }
    }
    return out;
  }
}

function atom(tok: string): Value {
  if (tok === '#t') return true;
  if (tok === '#f') return false;
  if (tok[0] === '#') throw syn('bad token: ' + tok);
  if (/^-?[0-9]+$/.test(tok)) {
    const v = BigInt(tok);
    if (v > MAXI || v < MINI) throw syn('integer out of range');
    return v;
  }
  if (tok === '.') throw syn('unexpected .');
  return new Sym(tok);
}

// ---------------------------------------------------------------- evaluator

const SPECIAL = new Set([
  'quote', 'if', 'define', 'set!', 'lambda', 'begin', 'let', 'let*', 'letrec',
  'cond', 'and', 'or', 'when', 'unless', 'try',
]);

const MAX_DEPTH = 10000;
let depth = 0;

function enter(): void {
  if (depth + 1 > MAX_DEPTH) throw rt('recursion limit exceeded');
  depth++;
}

function lookup(env: Frame, name: string): Value {
  for (let f: Frame | null = env; f !== null; f = f.parent) {
    const v = f.vars.get(name);
    if (v !== undefined) return v;
  }
  throw rt(`unbound variable: ${name}`);
}

function arityStr(min: number, max: number): string {
  if (min === max) return `${min}`;
  if (max === Infinity) return `at least ${min}`;
  return `${min} to ${max}`;
}

function callBuiltin(b: Builtin, args: Value[]): Value {
  const n = args.length;
  if (n < b.min || n > b.max) {
    throw rt(`wrong number of arguments to ${b.name}: expected ${arityStr(b.min, b.max)}, got ${n}`);
  }
  return b.fn(args);
}

function bindArgs(c: Closure, args: Value[]): Frame {
  const n = c.params.length;
  if (c.rest === null ? args.length !== n : args.length < n) {
    const name = c.name === null ? 'lambda' : c.name;
    const exp = c.rest === null ? `${n}` : `at least ${n}`;
    throw rt(`wrong number of arguments to ${name}: expected ${exp}, got ${args.length}`);
  }
  const fr = new Frame(c.env);
  for (let i = 0; i < n; i++) fr.vars.set(c.params[i], args[i]);
  if (c.rest !== null) fr.vars.set(c.rest, fromArray(args.slice(n)));
  return fr;
}

// Non-tail procedure call (used by builtins and try handlers).
function applyProc(fn: Value, args: Value[]): Value {
  if (fn instanceof Builtin) return callBuiltin(fn, args);
  if (fn instanceof Closure) {
    const fr = bindArgs(fn, args);
    enter();
    try {
      const b = fn.body;
      for (let k = 0; k < b.length - 1; k++) ev(b[k], fr, false);
      return ev(b[b.length - 1], fr, true);
    } finally {
      depth--;
    }
  }
  throw rt(`not a procedure: ${show(fn, true)}`);
}

// counted: true when the call depth for this body was already accounted for by the caller.
function ev(x0: Value, env0: Frame, counted0: boolean): Value {
  let x = x0;
  let env = env0;
  let counted = counted0;
  let own = false;
  try {
    for (;;) {
      if (x instanceof Sym) return lookup(env, x.name);
      if (!(x instanceof Pair)) {
        if (x === NIL) throw syn('empty application');
        return x;
      }
      let fn: Value;
      let args: Value[];
      const head = x.car;
      if (head instanceof Sym && SPECIAL.has(head.name)) {
        const r = special(head.name, x, env);
        if (r.k === 'val') return r.v;
        if (r.k === 'expr') { x = r.x; env = r.env; continue; }
        fn = r.fn;
        args = r.args;
      } else {
        let c: Value = x;
        while (c instanceof Pair) c = c.cdr;
        if (c !== NIL) throw syn('bad application');
        fn = ev(head, env, false);
        args = [];
        for (let a: Value = x.cdr; a instanceof Pair; a = a.cdr) args.push(ev(a.car, env, false));
      }

      if (fn instanceof Builtin) return callBuiltin(fn, args);
      if (fn instanceof Closure) {
        const fr = bindArgs(fn, args);
        if (!counted) { enter(); counted = true; own = true; }
        const b = fn.body;
        for (let k = 0; k < b.length - 1; k++) ev(b[k], fr, false);
        x = b[b.length - 1];
        env = fr;
        continue;
      }
      throw rt(`not a procedure: ${show(fn, true)}`);
    }
  } finally {
    if (own) depth--;
  }
}

type R =
  | { k: 'val'; v: Value }
  | { k: 'expr'; x: Value; env: Frame }
  | { k: 'call'; fn: Value; args: Value[] };

// Evaluate body forms arr[start..]; the last one is returned as a tail expression.
function seq(arr: Value[], start: number, env: Frame): R {
  if (start >= arr.length) return { k: 'val', v: VOID };
  for (let i = start; i < arr.length - 1; i++) ev(arr[i], env, false);
  return { k: 'expr', x: arr[arr.length - 1], env };
}

function parseParams(p: Value, kw: string): { params: string[]; rest: string | null } {
  const params: string[] = [];
  const seen = new Set<string>();
  if (p instanceof Sym) return { params, rest: p.name };
  let cur = p;
  while (cur instanceof Pair) {
    if (!(cur.car instanceof Sym) || seen.has(cur.car.name)) throw bad(kw);
    seen.add(cur.car.name);
    params.push(cur.car.name);
    cur = cur.cdr;
  }
  if (cur === NIL) return { params, rest: null };
  if (cur instanceof Sym && !seen.has(cur.name)) return { params, rest: cur.name };
  throw bad(kw);
}

function makeLambda(form: Pair, env: Frame, name: string | null): Closure {
  const arr = toArray(form);
  if (arr === null || arr.length < 3) throw bad('lambda');
  const { params, rest } = parseParams(arr[1], 'lambda');
  return new Closure(params, rest, arr.slice(2), env, name);
}

function evNamed(e: Value, env: Frame, name: string): Value {
  if (e instanceof Pair && e.car instanceof Sym && e.car.name === 'lambda') {
    return makeLambda(e, env, name);
  }
  return ev(e, env, false);
}

function parseBindings(v: Value, kw: string): { name: string; init: Value }[] {
  const arr = toArray(v);
  if (arr === null) throw bad(kw);
  return arr.map((b) => {
    const p = toArray(b);
    if (p === null || p.length !== 2 || !(p[0] instanceof Sym)) throw bad(kw);
    return { name: p[0].name, init: p[1] };
  });
}

function special(name: string, form: Pair, env: Frame): R {
  const arr = toArray(form);
  if (arr === null) throw bad(name);
  switch (name) {
    case 'quote': {
      if (arr.length !== 2) throw bad(name);
      return { k: 'val', v: arr[1] };
    }
    case 'if': {
      if (arr.length !== 3 && arr.length !== 4) throw bad(name);
      const t = ev(arr[1], env, false);
      if (t !== false) return { k: 'expr', x: arr[2], env };
      if (arr.length === 4) return { k: 'expr', x: arr[3], env };
      return { k: 'val', v: VOID };
    }
    case 'define': {
      if (arr.length < 2) throw bad(name);
      const target = arr[1];
      if (target instanceof Sym) {
        if (arr.length !== 3) throw bad(name);
        env.vars.set(target.name, evNamed(arr[2], env, target.name));
        return { k: 'val', v: VOID };
      }
      if (target instanceof Pair && target.car instanceof Sym) {
        if (arr.length < 3) throw bad(name);
        const { params, rest } = parseParams(target.cdr, name);
        const fname = target.car.name;
        env.vars.set(fname, new Closure(params, rest, arr.slice(2), env, fname));
        return { k: 'val', v: VOID };
      }
      throw bad(name);
    }
    case 'set!': {
      if (arr.length !== 3 || !(arr[1] instanceof Sym)) throw bad(name);
      const nm = arr[1].name;
      const v = ev(arr[2], env, false);
      for (let f: Frame | null = env; f !== null; f = f.parent) {
        if (f.vars.has(nm)) { f.vars.set(nm, v); return { k: 'val', v: VOID }; }
      }
      throw rt(`unbound variable: ${nm}`);
    }
    case 'lambda':
      return { k: 'val', v: makeLambda(form, env, null) };
    case 'begin':
      return seq(arr, 1, env);
    case 'let': {
      if (arr.length < 3) throw bad(name);
      if (arr[1] instanceof Sym) {
        // named let
        if (arr.length < 4) throw bad(name);
        const lname = arr[1].name;
        const binds = parseBindings(arr[2], name);
        const args = binds.map((b) => ev(b.init, env, false));
        const loopEnv = new Frame(env);
        const clo = new Closure(binds.map((b) => b.name), null, arr.slice(3), loopEnv, lname);
        loopEnv.vars.set(lname, clo);
        return { k: 'call', fn: clo, args };
      }
      const binds = parseBindings(arr[1], name);
      const vals = binds.map((b) => ev(b.init, env, false));
      const fr = new Frame(env);
      binds.forEach((b, i) => fr.vars.set(b.name, vals[i]));
      return seq(arr, 2, fr);
    }
    case 'let*':
    case 'letrec': {
      if (arr.length < 3) throw bad(name);
      const binds = parseBindings(arr[1], name);
      const fr = new Frame(env);
      for (const b of binds) fr.vars.set(b.name, ev(b.init, fr, false));
      return seq(arr, 2, fr);
    }
    case 'cond': {
      for (let i = 1; i < arr.length; i++) {
        const cl = toArray(arr[i]);
        if (cl === null || cl.length === 0) throw bad(name);
        if (cl[0] instanceof Sym && cl[0].name === 'else') {
          if (i !== arr.length - 1 || cl.length < 2) throw bad(name);
          return seq(cl, 1, env);
        }
        const t = ev(cl[0], env, false);
        if (t !== false) {
          if (cl.length === 1) return { k: 'val', v: t };
          return seq(cl, 1, env);
        }
      }
      return { k: 'val', v: VOID };
    }
    case 'and': {
      if (arr.length === 1) return { k: 'val', v: true };
      for (let i = 1; i < arr.length - 1; i++) {
        if (ev(arr[i], env, false) === false) return { k: 'val', v: false };
      }
      return { k: 'expr', x: arr[arr.length - 1], env };
    }
    case 'or': {
      if (arr.length === 1) return { k: 'val', v: false };
      for (let i = 1; i < arr.length - 1; i++) {
        const v = ev(arr[i], env, false);
        if (v !== false) return { k: 'val', v };
      }
      return { k: 'expr', x: arr[arr.length - 1], env };
    }
    case 'when':
    case 'unless': {
      if (arr.length < 3) throw bad(name);
      const t = ev(arr[1], env, false);
      const fire = name === 'when' ? t !== false : t === false;
      if (!fire) return { k: 'val', v: VOID };
      return seq(arr, 2, env);
    }
    case 'try': {
      if (arr.length !== 3) throw bad(name);
      let msg: string;
      try {
        return { k: 'val', v: ev(arr[1], env, false) };
      } catch (e) {
        if (e instanceof SErr && !e.syntax) msg = e.msg;
        else if (e instanceof RangeError) msg = 'recursion limit exceeded';
        else throw e;
      }
      const h = ev(arr[2], env, false);
      return { k: 'val', v: applyProc(h, [msg]) };
    }
  }
  throw bad(name);
}

// ---------------------------------------------------------------- printing

function quoteStr(s: string): string {
  let o = '"';
  for (const c of s) {
    if (c === '\\') o += '\\\\';
    else if (c === '"') o += '\\"';
    else if (c === '\n') o += '\\n';
    else if (c === '\t') o += '\\t';
    else o += c;
  }
  return o + '"';
}

function show(v: Value, wr: boolean): string {
  if (typeof v === 'bigint') return v.toString();
  if (typeof v === 'boolean') return v ? '#t' : '#f';
  if (typeof v === 'string') return wr ? quoteStr(v) : v;
  if (v instanceof Sym) return v.name;
  if (v === NIL) return '()';
  if (v === VOID) return '#<void>';
  if (v instanceof Closure) return v.name === null ? '#<procedure>' : `#<procedure ${v.name}>`;
  if (v instanceof Builtin) return `#<builtin ${v.name}>`;
  const parts: string[] = ['('];
  let cur: Value = v;
  let first = true;
  while (cur instanceof Pair) {
    if (!first) parts.push(' ');
    parts.push(show(cur.car, wr));
    first = false;
    cur = cur.cdr;
  }
  if (cur !== NIL) { parts.push(' . '); parts.push(show(cur, wr)); }
  parts.push(')');
  return parts.join('');
}

// ---------------------------------------------------------------- builtins

const G = new Frame(null);
function def(name: string, min: number, max: number, fn: (a: Value[]) => Value): void {
  G.vars.set(name, new Builtin(name, min, max, fn));
}

let outParts: string[] = [];
let pendingNL = false; // output so far is non-empty and does not end in newline
function out(s: string): void {
  if (s.length === 0) return;
  outParts.push(s);
  pendingNL = s[s.length - 1] !== '\n';
}

function needInt(v: Value, name: string): bigint {
  if (typeof v === 'bigint') return v;
  throw rt(`${name}: expected integer, got ${show(v, true)}`);
}
function needStr(v: Value, name: string): string {
  if (typeof v === 'string') return v;
  throw rt(`${name}: expected string, got ${show(v, true)}`);
}
function needList(v: Value, name: string): Value[] {
  const arr = toArray(v);
  if (arr === null) throw rt(`${name}: expected list, got ${show(v, true)}`);
  return arr;
}
function needPair(v: Value, name: string): Pair {
  if (v instanceof Pair) return v;
  throw rt(`${name}: expected pair, got ${show(v, true)}`);
}
function needSym(v: Value, name: string): Sym {
  if (v instanceof Sym) return v;
  throw rt(`${name}: expected symbol, got ${show(v, true)}`);
}
function needProc(v: Value, name: string): Value {
  if (v instanceof Closure || v instanceof Builtin) return v;
  throw rt(`${name}: expected procedure, got ${show(v, true)}`);
}

function eqv(a: Value, b: Value): boolean {
  if (typeof a === 'bigint' && typeof b === 'bigint') return a === b;
  if (typeof a === 'boolean' && typeof b === 'boolean') return a === b;
  if (a instanceof Sym && b instanceof Sym) return a.name === b.name;
  if (a === NIL && b === NIL) return true;
  return false;
}

function equal(a: Value, b: Value): boolean {
  for (;;) {
    if (a instanceof Pair && b instanceof Pair) {
      if (!equal(a.car, b.car)) return false;
      a = a.cdr;
      b = b.cdr;
      continue;
    }
    if (a instanceof Sym && b instanceof Sym) return a.name === b.name;
    return a === b;
  }
}

function cmpChain(name: string, a: Value[], op: (x: bigint, y: bigint) => boolean): boolean {
  for (const v of a) needInt(v, name);
  for (let i = 0; i + 1 < a.length; i++) {
    if (!op(a[i] as bigint, a[i + 1] as bigint)) return false;
  }
  return true;
}

function cxr(name: string): void {
  const ops = name.slice(1, -1).split('').reverse(); // apply right to left
  def(name, 1, 1, (a) => {
    let cur: Value = a[0];
    for (const op of ops) {
      if (!(cur instanceof Pair)) throw rt(`${name}: expected pair, got ${show(cur, true)}`);
      cur = op === 'a' ? cur.car : cur.cdr;
    }
    return cur;
  });
}

function msort(a: Value[], less: Value): Value[] {
  if (a.length <= 1) return a;
  const mid = a.length >> 1;
  const l = msort(a.slice(0, mid), less);
  const r = msort(a.slice(mid), less);
  const res: Value[] = [];
  let i = 0;
  let j = 0;
  while (i < l.length && j < r.length) {
    if (applyProc(less, [r[j], l[i]]) !== false) res.push(r[j++]);
    else res.push(l[i++]);
  }
  while (i < l.length) res.push(l[i++]);
  while (j < r.length) res.push(r[j++]);
  return res;
}

function installBuiltins(): void {
  // numbers
  def('+', 0, Infinity, (a) => {
    a.forEach((v) => needInt(v, '+'));
    let s = 0n;
    for (const v of a) s = ck(s + (v as bigint));
    return s;
  });
  def('-', 1, Infinity, (a) => {
    a.forEach((v) => needInt(v, '-'));
    if (a.length === 1) return ck(-(a[0] as bigint));
    let s = a[0] as bigint;
    for (let i = 1; i < a.length; i++) s = ck(s - (a[i] as bigint));
    return s;
  });
  def('*', 0, Infinity, (a) => {
    a.forEach((v) => needInt(v, '*'));
    let s = 1n;
    for (const v of a) s = ck(s * (v as bigint));
    return s;
  });
  def('quotient', 2, 2, (a) => {
    const x = needInt(a[0], 'quotient');
    const y = needInt(a[1], 'quotient');
    if (y === 0n) throw rt('division by zero');
    return ck(x / y);
  });
  def('remainder', 2, 2, (a) => {
    const x = needInt(a[0], 'remainder');
    const y = needInt(a[1], 'remainder');
    if (y === 0n) throw rt('division by zero');
    return x % y;
  });
  def('modulo', 2, 2, (a) => {
    const x = needInt(a[0], 'modulo');
    const y = needInt(a[1], 'modulo');
    if (y === 0n) throw rt('division by zero');
    let r = x % y;
    if (r !== 0n && (r < 0n) !== (y < 0n)) r += y;
    return r;
  });
  def('abs', 1, 1, (a) => {
    const x = needInt(a[0], 'abs');
    return ck(x < 0n ? -x : x);
  });
  def('min', 1, Infinity, (a) => {
    a.forEach((v) => needInt(v, 'min'));
    let m = a[0] as bigint;
    for (const v of a) if ((v as bigint) < m) m = v as bigint;
    return m;
  });
  def('max', 1, Infinity, (a) => {
    a.forEach((v) => needInt(v, 'max'));
    let m = a[0] as bigint;
    for (const v of a) if ((v as bigint) > m) m = v as bigint;
    return m;
  });
  def('=', 2, Infinity, (a) => cmpChain('=', a, (x, y) => x === y));
  def('<', 2, Infinity, (a) => cmpChain('<', a, (x, y) => x < y));
  def('>', 2, Infinity, (a) => cmpChain('>', a, (x, y) => x > y));
  def('<=', 2, Infinity, (a) => cmpChain('<=', a, (x, y) => x <= y));
  def('>=', 2, Infinity, (a) => cmpChain('>=', a, (x, y) => x >= y));
  def('zero?', 1, 1, (a) => needInt(a[0], 'zero?') === 0n);
  def('even?', 1, 1, (a) => needInt(a[0], 'even?') % 2n === 0n);
  def('odd?', 1, 1, (a) => needInt(a[0], 'odd?') % 2n !== 0n);

  // predicates and equality
  def('not', 1, 1, (a) => a[0] === false);
  def('null?', 1, 1, (a) => a[0] === NIL);
  def('pair?', 1, 1, (a) => a[0] instanceof Pair);
  def('list?', 1, 1, (a) => toArray(a[0]) !== null);
  def('number?', 1, 1, (a) => typeof a[0] === 'bigint');
  def('string?', 1, 1, (a) => typeof a[0] === 'string');
  def('symbol?', 1, 1, (a) => a[0] instanceof Sym);
  def('boolean?', 1, 1, (a) => typeof a[0] === 'boolean');
  def('procedure?', 1, 1, (a) => a[0] instanceof Closure || a[0] instanceof Builtin);
  def('eq?', 2, 2, (a) => eqv(a[0], a[1]));
  def('equal?', 2, 2, (a) => equal(a[0], a[1]));

  // pairs and lists
  def('cons', 2, 2, (a) => new Pair(a[0], a[1]));
  def('car', 1, 1, (a) => needPair(a[0], 'car').car);
  def('cdr', 1, 1, (a) => needPair(a[0], 'cdr').cdr);
  cxr('caar'); cxr('cadr'); cxr('cdar'); cxr('cddr');
  cxr('caddr');
  def('set-car!', 2, 2, (a) => { needPair(a[0], 'set-car!').car = a[1]; return VOID; });
  def('set-cdr!', 2, 2, (a) => { needPair(a[0], 'set-cdr!').cdr = a[1]; return VOID; });
  def('list', 0, Infinity, (a) => fromArray(a));
  def('length', 1, 1, (a) => BigInt(needList(a[0], 'length').length));
  def('append', 0, Infinity, (a) => {
    if (a.length === 0) return NIL;
    const lists: Value[][] = [];
    for (let i = 0; i < a.length - 1; i++) lists.push(needList(a[i], 'append'));
    let res: Value = a[a.length - 1];
    for (let i = lists.length - 1; i >= 0; i--) res = fromArray(lists[i], res);
    return res;
  });
  def('reverse', 1, 1, (a) => fromArray(needList(a[0], 'reverse').slice().reverse()));
  def('list-ref', 2, 2, (a) => {
    const arr = needList(a[0], 'list-ref');
    const k = needInt(a[1], 'list-ref');
    if (k < 0n || k >= BigInt(arr.length)) throw rt('list-ref: index out of range');
    return arr[Number(k)];
  });
  def('list-tail', 2, 2, (a) => {
    const arr = needList(a[0], 'list-tail');
    const k = needInt(a[1], 'list-tail');
    if (k < 0n || k > BigInt(arr.length)) throw rt('list-tail: index out of range');
    let cur: Value = a[0];
    for (let i = 0; i < Number(k); i++) cur = (cur as Pair).cdr;
    return cur;
  });
  def('range', 2, 2, (a) => {
    const lo = needInt(a[0], 'range');
    const hi = needInt(a[1], 'range');
    let r: Value = NIL;
    for (let i = hi - 1n; i >= lo; i--) r = new Pair(i, r);
    return r;
  });
  def('assoc', 2, 2, (a) => {
    const alist = needList(a[1], 'assoc');
    for (const e of alist) {
      if (!(e instanceof Pair)) throw rt(`assoc: expected pair, got ${show(e, true)}`);
      if (equal(a[0], e.car)) return e;
    }
    return false;
  });
  def('member', 2, 2, (a) => {
    needList(a[1], 'member');
    let cur: Value = a[1];
    while (cur instanceof Pair) {
      if (equal(a[0], cur.car)) return cur;
      cur = cur.cdr;
    }
    return false;
  });

  // higher-order
  def('map', 2, Infinity, (a) => {
    const f = needProc(a[0], 'map');
    const lists = a.slice(1).map((l) => needList(l, 'map'));
    const n = Math.min(...lists.map((l) => l.length));
    const res: Value[] = [];
    for (let i = 0; i < n; i++) res.push(applyProc(f, lists.map((l) => l[i])));
    return fromArray(res);
  });
  def('for-each', 2, Infinity, (a) => {
    const f = needProc(a[0], 'for-each');
    const lists = a.slice(1).map((l) => needList(l, 'for-each'));
    const n = Math.min(...lists.map((l) => l.length));
    for (let i = 0; i < n; i++) applyProc(f, lists.map((l) => l[i]));
    return VOID;
  });
  def('filter', 2, 2, (a) => {
    const f = needProc(a[0], 'filter');
    const arr = needList(a[1], 'filter');
    const res: Value[] = [];
    for (const e of arr) if (applyProc(f, [e]) !== false) res.push(e);
    return fromArray(res);
  });
  def('fold', 3, 3, (a) => {
    const f = needProc(a[0], 'fold');
    const arr = needList(a[2], 'fold');
    let acc = a[1];
    for (const e of arr) acc = applyProc(f, [acc, e]);
    return acc;
  });
  def('foldr', 3, 3, (a) => {
    const f = needProc(a[0], 'foldr');
    const arr = needList(a[2], 'foldr');
    let acc = a[1];
    for (let i = arr.length - 1; i >= 0; i--) acc = applyProc(f, [arr[i], acc]);
    return acc;
  });
  def('apply', 2, Infinity, (a) => {
    const f = needProc(a[0], 'apply');
    const last = needList(a[a.length - 1], 'apply');
    return applyProc(f, a.slice(1, -1).concat(last));
  });
  def('sort', 2, 2, (a) => {
    const less = needProc(a[1], 'sort');
    const arr = needList(a[0], 'sort');
    return fromArray(msort(arr, less));
  });

  // strings
  def('string-length', 1, 1, (a) => BigInt(needStr(a[0], 'string-length').length));
  def('string-append', 0, Infinity, (a) => {
    a.forEach((v) => needStr(v, 'string-append'));
    return (a as string[]).join('');
  });
  def('substring', 3, 3, (a) => {
    const s = needStr(a[0], 'substring');
    const st = needInt(a[1], 'substring');
    const en = needInt(a[2], 'substring');
    if (st < 0n || st > en || en > BigInt(s.length)) throw rt('substring: index out of range');
    return s.slice(Number(st), Number(en));
  });
  def('string-ref', 2, 2, (a) => {
    const s = needStr(a[0], 'string-ref');
    const k = needInt(a[1], 'string-ref');
    if (k < 0n || k >= BigInt(s.length)) throw rt('string-ref: index out of range');
    return s[Number(k)];
  });
  def('string=?', 2, 2, (a) => needStr(a[0], 'string=?') === needStr(a[1], 'string=?'));
  def('string<?', 2, 2, (a) => needStr(a[0], 'string<?') < needStr(a[1], 'string<?'));
  def('string-upcase', 1, 1, (a) => needStr(a[0], 'string-upcase').replace(/[a-z]/g, (c) => c.toUpperCase()));
  def('string-downcase', 1, 1, (a) => needStr(a[0], 'string-downcase').replace(/[A-Z]/g, (c) => c.toLowerCase()));
  def('string->number', 1, 1, (a) => {
    const s = needStr(a[0], 'string->number');
    if (!/^-?[0-9]+$/.test(s)) return false;
    const v = BigInt(s);
    return v > MAXI || v < MINI ? false : v;
  });
  def('number->string', 1, 1, (a) => needInt(a[0], 'number->string').toString());
  def('string->symbol', 1, 1, (a) => new Sym(needStr(a[0], 'string->symbol')));
  def('symbol->string', 1, 1, (a) => needSym(a[0], 'symbol->string').name);
  def('string->list', 1, 1, (a) => fromArray(needStr(a[0], 'string->list').split('')));
  def('list->string', 1, 1, (a) => {
    const arr = needList(a[0], 'list->string');
    return arr.map((e) => needStr(e, 'list->string')).join('');
  });
  def('string-join', 2, 2, (a) => {
    const arr = needList(a[0], 'string-join').map((e) => needStr(e, 'string-join'));
    return arr.join(needStr(a[1], 'string-join'));
  });
  def('string-split', 2, 2, (a) => {
    const s = needStr(a[0], 'string-split');
    const sep = needStr(a[1], 'string-split');
    if (sep.length !== 1) throw rt('string-split: separator must be one character');
    return fromArray(s.split(sep));
  });
  def('string-contains?', 2, 2, (a) => needStr(a[0], 'string-contains?').includes(needStr(a[1], 'string-contains?')));

  // other
  def('display', 1, 1, (a) => { out(show(a[0], false)); return VOID; });
  def('write', 1, 1, (a) => { out(show(a[0], true)); return VOID; });
  def('newline', 0, 0, () => { out('\n'); return VOID; });
  def('void', 0, 0, () => VOID);
  def('error', 1, Infinity, (a) => {
    const m = a[0];
    if (typeof m !== 'string') throw rt(`error: expected string, got ${show(m, true)}`);
    throw rt(m + a.slice(1).map((v) => ' ' + show(v, true)).join(''));
  });
}

// ---------------------------------------------------------------- driver

function run(src: string): string {
  installBuiltins();
  const rd = new Reader(src);
  for (;;) {
    try {
      const form = rd.top();
      if (form === EOF_SENTINEL) break;
      ev(form, G, false);
    } catch (e) {
      let msg: string;
      if (e instanceof SErr) msg = e.msg;
      else if (e instanceof RangeError) msg = 'recursion limit exceeded';
      else throw e;
      if (pendingNL) out('\n');
      out('error: ' + msg + '\n');
      break;
    }
  }
  return outParts.join('');
}

if (isMainThread) {
  const src = fs.readFileSync(0, 'utf8');
  const w = new Worker(new URL(import.meta.url), {
    workerData: src,
    resourceLimits: { stackSizeMb: 256, maxOldGenerationSizeMb: 4096 },
  });
  let result = '';
  let got = false;
  w.on('message', (s: string) => { result = s; got = true; });
  w.on('error', (e) => {
    process.stderr.write(String(e) + '\n');
  });
  w.on('exit', () => {
    if (got) process.stdout.write(result);
  });
} else {
  const res = run(workerData as string);
  parentPort!.postMessage(res);
}
