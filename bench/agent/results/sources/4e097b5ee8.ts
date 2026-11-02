// make-lite: a simulator of a small make-like build tool. See TASK.md.
import * as fs from 'node:fs';

class Stop extends Error {}

type Var = { rec: boolean; value: string; cli: boolean };
type Recipe = { text: string; line: number };
type Entry = { name: string; normal: string[]; oo: string[]; recipe: Recipe[] };
type PatRule = { pattern: string; normal: string[]; oo: string[]; recipe: Recipe[] };
type Rule = { normal: string[]; oo: string[]; recipe: Recipe[]; stem: string };
type Auto = Record<string, string> | null;
type Block = { on: boolean; parentOn: boolean; cond: boolean; inElse: boolean; line: number };
type OpenRule = { entries: Entry[]; pats: PatRule[]; recipe: Recipe[]; line: number; special: boolean };

// ---------- global state ----------
const out: string[] = [];
let makeLines: string[] = [];
const table = new Map<string, number>();
let clock = 0;
let curLine: number | null = null;
let vars = new Map<string, Var>();
let explicit = new Map<string, Entry>();
let explicitOrder: string[] = [];
let patterns: PatRule[] = [];
let phony = new Set<string>();
let phonyOrder: string[] = [];
let bindings = new Map<string, string>();
let expStack: string[] = [];
let dryMode = false;
let memo = new Map<string, boolean>();
let stack: string[] = [];
let recipeCount = 0;

const AUTO = new Set(['@', '<', '^', '?', '*', '|']);
const FUNCS = new Set([
  'subst', 'patsubst', 'strip', 'findstring', 'filter', 'filter-out', 'sort',
  'word', 'wordlist', 'words', 'firstword', 'lastword', 'dir', 'notdir',
  'suffix', 'basename', 'addprefix', 'addsuffix', 'wildcard', 'foreach', 'if',
  'info', 'error',
]);

// ---------- errors ----------
function fatal(msg: string): never {
  out.push(curLine === null ? `make: *** ${msg}.  Stop.` : `Makefile:${curLine}: *** ${msg}.  Stop.`);
  throw new Stop();
}
function stopWith(line: string): never {
  out.push(line);
  throw new Stop();
}

// ---------- small helpers ----------
const words = (s: string): string[] => s.split(/\s+/).filter((w) => w !== '');
const trimSpTab = (s: string): string => s.replace(/^[ \t]+|[ \t]+$/g, '');
const dedupe = <T,>(a: T[]): T[] => [...new Set(a)];
const byteCmp = (a: string, b: string): number => Buffer.compare(Buffer.from(a), Buffer.from(b));
const nz = (a: string[]): string => a.filter((x) => x !== '').join(' ');
const lastComp = (w: string): string => w.slice(w.lastIndexOf('/') + 1);
const joinVals = (a: string, b: string): string => (a !== '' && b !== '' ? a + ' ' + b : a + b);

function replaceFirst(s: string, from: string, to: string): string {
  const i = s.indexOf(from);
  return i < 0 ? s : s.slice(0, i) + to + s.slice(i + from.length);
}

// Index just after the close bracket matching an open one that precedes `start`.
function findClose(s: string, start: number, open: string, close: string): number {
  let depth = 1;
  for (let k = start; k < s.length; k++) {
    if (s[k] === open) depth++;
    else if (s[k] === close) {
      depth--;
      if (depth === 0) return k;
    }
  }
  return -1;
}

// Match one word against a pattern with at most one '%'. Returns the stem or null.
function matchPat(pat: string, w: string): string | null {
  const i = pat.indexOf('%');
  if (i < 0) return pat === w ? '' : null;
  const pre = pat.slice(0, i);
  const suf = pat.slice(i + 1);
  if (w.length < pre.length + suf.length || !w.startsWith(pre) || !w.endsWith(suf)) return null;
  return w.slice(pre.length, w.length - suf.length);
}

function patsubstWord(pat: string, rep: string, w: string): string | null {
  const stem = matchPat(pat, w);
  if (stem === null) return null;
  if (!pat.includes('%')) return rep;
  return replaceFirst(rep, '%', stem);
}

function splitArgs(s: string): string[] {
  const parts: string[] = [];
  let depth = 0;
  let cur = 0;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (c === '(' || c === '{') depth++;
    else if (c === ')' || c === '}') {
      if (depth > 0) depth--;
    } else if (c === ',' && depth === 0) {
      parts.push(s.slice(cur, i));
      cur = i + 1;
    }
  }
  parts.push(s.slice(cur));
  return parts;
}

function globRe(p: string): RegExp {
  let r = '';
  for (const c of p) {
    if (c === '*') r += '[^/]*';
    else if (c === '?') r += '[^/]';
    else r += c.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }
  return new RegExp('^' + r + '$');
}

// ---------- expansion ----------
function lookupVar(name: string, auto: Auto): string {
  const b = bindings.get(name);
  if (b !== undefined) return b;
  if (AUTO.has(name)) return auto ? (auto[name] ?? '') : '';
  const v = vars.get(name);
  if (!v) return '';
  if (!v.rec) return v.value;
  if (expStack.includes(name)) {
    fatal(`Recursive variable '${name}' references itself (eventually)`);
  }
  expStack.push(name);
  try {
    return expand(v.value, auto);
  } finally {
    expStack.pop();
  }
}

function expand(s: string, auto: Auto): string {
  let res = '';
  let i = 0;
  while (i < s.length) {
    const c = s[i];
    if (c !== '$') {
      res += c;
      i++;
      continue;
    }
    if (i + 1 >= s.length) break; // lone '$' at end is dropped
    const n = s[i + 1];
    if (n === '$') {
      res += '$';
      i += 2;
      continue;
    }
    if (n === '(' || n === '{') {
      const close = n === '(' ? ')' : '}';
      const j = findClose(s, i + 2, n, close);
      if (j < 0) fatal('unterminated variable reference');
      res += evalRef(s.slice(i + 2, j), auto);
      i = j + 1;
      continue;
    }
    res += lookupVar(n, auto);
    i += 2;
  }
  return res;
}

function evalRef(inner: string, auto: Auto): string {
  const m = /^([^ \t]+)[ \t]/.exec(inner);
  if (m && FUNCS.has(m[1])) return callFunc(m[1], inner.slice(m[0].length), auto);
  const name = expand(inner, auto);
  const colon = name.indexOf(':');
  if (colon > 0) {
    const eq = name.indexOf('=', colon + 1);
    if (eq >= 0) {
      const v = lookupVar(name.slice(0, colon).trim(), auto);
      const from = name.slice(colon + 1, eq);
      const to = name.slice(eq + 1);
      const pat = from.includes('%') ? from : '%' + from;
      const rep = from.includes('%') ? to : '%' + to;
      return nz(words(v).map((w) => patsubstWord(pat, rep, w) ?? w));
    }
  }
  return lookupVar(name.trim(), auto);
}

function callFunc(name: string, raw: string, auto: Auto): string {
  const args = splitArgs(raw).map(trimSpTab);
  const arg = (i: number): string => (i < args.length ? args[i] : '');
  const ex = (i: number): string => expand(arg(i), auto);
  switch (name) {
    case 'subst': {
      const from = ex(0);
      const to = ex(1);
      const text = ex(2);
      return from === '' ? text : text.split(from).join(to);
    }
    case 'patsubst': {
      const pat = ex(0);
      const rep = ex(1);
      return nz(words(ex(2)).map((w) => patsubstWord(pat, rep, w) ?? w));
    }
    case 'strip':
      return words(ex(0)).join(' ');
    case 'findstring': {
      const f = ex(0);
      const x = ex(1);
      return x.includes(f) ? f : '';
    }
    case 'filter': {
      const pats = words(ex(0));
      return words(ex(1)).filter((w) => pats.some((p) => matchPat(p, w) !== null)).join(' ');
    }
    case 'filter-out': {
      const pats = words(ex(0));
      return words(ex(1)).filter((w) => !pats.some((p) => matchPat(p, w) !== null)).join(' ');
    }
    case 'sort':
      return dedupe(words(ex(0)).sort(byteCmp)).join(' ');
    case 'word': {
      const n = ex(0).trim();
      const ws = words(ex(1));
      if (!/^\d+$/.test(n)) return '';
      const k = Number(n);
      return k >= 1 && k <= ws.length ? ws[k - 1] : '';
    }
    case 'wordlist': {
      const s = ex(0).trim();
      const e = ex(1).trim();
      const ws = words(ex(2));
      if (!/^-?\d+$/.test(s) || !/^-?\d+$/.test(e)) return '';
      const a = Number(s);
      const b = Number(e);
      if (a < 1 || b < a || a > ws.length) return '';
      return ws.slice(a - 1, b).join(' ');
    }
    case 'words':
      return String(words(ex(0)).length);
    case 'firstword':
      return words(ex(0))[0] ?? '';
    case 'lastword': {
      const ws = words(ex(0));
      return ws.length ? ws[ws.length - 1] : '';
    }
    case 'dir':
      return words(ex(0))
        .map((w) => {
          const i = w.lastIndexOf('/');
          return i < 0 ? './' : w.slice(0, i + 1);
        })
        .join(' ');
    case 'notdir':
      return nz(words(ex(0)).map((w) => lastComp(w)));
    case 'suffix':
      return nz(
        words(ex(0)).map((w) => {
          const b = lastComp(w);
          const d = b.lastIndexOf('.');
          return d < 0 ? '' : b.slice(d);
        }),
      );
    case 'basename':
      return nz(
        words(ex(0)).map((w) => {
          const b = lastComp(w);
          const d = b.lastIndexOf('.');
          return d < 0 ? w : w.slice(0, w.length - (b.length - d));
        }),
      );
    case 'addprefix': {
      const p = ex(0);
      return words(ex(1)).map((w) => p + w).join(' ');
    }
    case 'addsuffix': {
      const s = ex(0);
      return words(ex(1)).map((w) => w + s).join(' ');
    }
    case 'wildcard': {
      const res: string[] = [];
      for (const p of words(ex(0))) {
        const re = globRe(p);
        res.push(...[...table.keys()].filter((f) => re.test(f)).sort(byteCmp));
      }
      return res.join(' ');
    }
    case 'foreach': {
      const v = ex(0).trim();
      const list = words(ex(1));
      const body = arg(2);
      const res: string[] = [];
      for (const w of list) {
        const had = bindings.has(v);
        const old = bindings.get(v);
        bindings.set(v, w);
        try {
          res.push(expand(body, auto));
        } finally {
          if (had) bindings.set(v, old as string);
          else bindings.delete(v);
        }
      }
      return res.join(' ');
    }
    case 'if': {
      const c = ex(0).trim();
      return c !== '' ? ex(1) : ex(2);
    }
    case 'info':
      out.push(ex(0));
      return '';
    case 'error':
      return fatal(ex(0));
    default:
      return '';
  }
}

// ---------- makefile parsing ----------
function logicalLines(phys: string[]): { text: string; num: number }[] {
  const res: { text: string; num: number }[] = [];
  let i = 0;
  while (i < phys.length) {
    const num = i + 1;
    let s = phys[i++];
    while (s.endsWith('\\') && i < phys.length) {
      s = s.slice(0, -1).replace(/[ \t]+$/, '') + ' ' + phys[i++].replace(/^[ \t]+/, '');
    }
    res.push({ text: s, num });
  }
  return res;
}

function stripComment(s: string): string {
  let res = '';
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (c === '\\' && s[i + 1] === '#') {
      res += '#';
      i++;
      continue;
    }
    if (c === '#') break;
    res += c;
  }
  return res;
}

// Index of the first top-level ':' (outside $(...) / ${...}), before any ';'.
function findTopColon(s: string): number {
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (c === '$') {
      const n = s[i + 1];
      if (n === '(' || n === '{') {
        const j = findClose(s, i + 2, n, n === '(' ? ')' : '}');
        if (j < 0) return -1;
        i = j;
      } else {
        i++;
      }
      continue;
    }
    if (c === ';') return -1;
    if (c === ':') return i;
  }
  return -1;
}

function isAssign(t: string): boolean {
  const eq = t.indexOf('=');
  if (eq < 0) return false;
  const col = findTopColon(t);
  return col < 0 || col > eq || col === eq - 1;
}

function directive(t: string): { kind: string; rest: string } | null {
  const m = /^(ifdef|ifndef|ifeq|ifneq|else|endif)(?=[ \t(]|$)/.exec(t);
  if (!m) return null;
  return { kind: m[1], rest: t.slice(m[1].length).trim() };
}

function parseIfeqArgs(rest: string): [string, string] {
  if (rest.length < 2 || !rest.startsWith('(') || !rest.endsWith(')')) {
    fatal('invalid syntax in conditional');
  }
  const inner = rest.slice(1, -1);
  const commas: number[] = [];
  let depth = 0;
  for (let i = 0; i < inner.length; i++) {
    const c = inner[i];
    if (c === '(' || c === '{') depth++;
    else if (c === ')' || c === '}') {
      if (depth > 0) depth--;
    } else if (c === ',' && depth === 0) commas.push(i);
  }
  if (commas.length !== 1) fatal('invalid syntax in conditional');
  const c = commas[0];
  const a = expand(trimSpTab(inner.slice(0, c)), null).trim();
  const b = expand(trimSpTab(inner.slice(c + 1)), null).trim();
  return [a, b];
}

function parseMakefile(): void {
  explicit = new Map();
  explicitOrder = [];
  patterns = [];
  phony = new Set();
  phonyOrder = [];
  curLine = null;

  const blocks: Block[] = [];
  let open: OpenRule | null = null;

  const closeRule = (): void => {
    if (!open) return;
    const r: OpenRule = open;
    open = null;
    if (r.special) return;
    if (r.recipe.length > 0) {
      for (const e of new Set(r.entries)) {
        if (e.recipe.length > 0) {
          out.push(`Makefile:${r.line}: warning: overriding recipe for target '${e.name}'`);
        }
        e.recipe = r.recipe;
      }
    }
    for (const p of r.pats) p.recipe = r.recipe;
  };

  const doAssign = (t: string, num: number): void => {
    const eq = t.indexOf('=');
    const pc = eq > 0 ? t[eq - 1] : '';
    const isOp = pc === ':' || pc === '?' || pc === '+';
    const opStart = isOp ? eq - 1 : eq;
    const op = isOp ? pc + '=' : '=';
    const name = expand(t.slice(0, opStart), null).trim();
    const value = trimSpTab(t.slice(eq + 1));
    if (name === '') fatal('empty variable name');
    const cur = vars.get(name);
    if (cur && cur.cli) return; // command-line variables win
    switch (op) {
      case '=':
        vars.set(name, { rec: true, value, cli: false });
        break;
      case ':=':
        vars.set(name, { rec: false, value: expand(value, null), cli: false });
        break;
      case '?=':
        if (!cur) vars.set(name, { rec: true, value, cli: false });
        break;
      case '+=':
        if (!cur) vars.set(name, { rec: true, value, cli: false });
        else if (!cur.rec) {
          vars.set(name, { rec: false, value: joinVals(cur.value, expand(value, null)), cli: false });
        } else {
          vars.set(name, { rec: true, value: joinVals(cur.value, value), cli: false });
        }
        break;
    }
    void num;
  };

  const doRule = (t: string, num: number): void => {
    const col = findTopColon(t);
    const semi = t.indexOf(';', col + 1);
    const tgtText = t.slice(0, col);
    const preText = semi >= 0 ? t.slice(col + 1, semi) : t.slice(col + 1);
    const cmd = semi >= 0 ? t.slice(semi + 1) : null;
    const targets = dedupe(words(expand(tgtText, null)));
    const pe = expand(preText, null);
    const bar = pe.indexOf('|');
    const normal = words(bar < 0 ? pe : pe.slice(0, bar));
    const oo = bar < 0 ? [] : words(pe.slice(bar + 1));
    const recipe: Recipe[] = cmd !== null ? [{ text: cmd, line: num }] : [];

    if (targets.length === 1 && targets[0] === '.PHONY') {
      for (const p of normal.concat(oo)) {
        if (!phony.has(p)) {
          phony.add(p);
          phonyOrder.push(p);
        }
      }
      open = { entries: [], pats: [], recipe, line: num, special: true };
      return;
    }

    const entries: Entry[] = [];
    const pats: PatRule[] = [];
    for (const tg of targets) {
      if (tg.includes('%')) {
        const pr: PatRule = { pattern: tg, normal: normal.slice(), oo: oo.slice(), recipe: [] };
        patterns.push(pr);
        pats.push(pr);
      } else {
        let e = explicit.get(tg);
        if (!e) {
          e = { name: tg, normal: [], oo: [], recipe: [] };
          explicit.set(tg, e);
          explicitOrder.push(tg);
        }
        e.normal.push(...normal);
        e.oo.push(...oo);
        entries.push(e);
      }
    }
    open = { entries, pats, recipe, line: num, special: false };
  };

  const handleDirective = (kind: string, rest: string, num: number): void => {
    const top = blocks.length ? blocks[blocks.length - 1] : null;
    if (kind === 'ifdef' || kind === 'ifndef' || kind === 'ifeq' || kind === 'ifneq') {
      const parentOn = top === null || top.on;
      if (!parentOn) {
        blocks.push({ on: false, parentOn: false, cond: false, inElse: false, line: num });
        return;
      }
      let cond: boolean;
      if (kind === 'ifdef' || kind === 'ifndef') {
        const name = expand(rest, null).trim();
        const v = vars.get(name);
        const defined = v !== undefined && v.value !== '';
        cond = kind === 'ifdef' ? defined : !defined;
      } else {
        const [a, b] = parseIfeqArgs(rest);
        cond = (kind === 'ifeq') === (a === b);
      }
      blocks.push({ on: cond, parentOn: true, cond, inElse: false, line: num });
    } else if (kind === 'else') {
      if (!top) fatal("extraneous 'else'");
      if (top.inElse) fatal("extraneous 'else'");
      top.inElse = true;
      top.on = top.parentOn && !top.cond;
    } else {
      if (!top) fatal("extraneous 'endif'");
      blocks.pop();
    }
  };

  for (const { text, num } of logicalLines(makeLines)) {
    const active = blocks.length === 0 || blocks[blocks.length - 1].on;
    if (text.startsWith('\t')) {
      const body = text.replace(/^\t+/, '');
      if (body.trim() === '' || !active) continue;
      curLine = num;
      if (!open) fatal('recipe commences before first target');
      (open as OpenRule).recipe.push({ text: body, line: num });
      continue;
    }
    const t = trimSpTab(stripComment(text));
    if (t === '') continue;
    const d = directive(t);
    if (d) {
      closeRule();
      curLine = num;
      handleDirective(d.kind, d.rest, num);
      continue;
    }
    if (!active) continue;
    closeRule();
    curLine = num;
    if (isAssign(t)) doAssign(t, num);
    else if (findTopColon(t) >= 0) doRule(t, num);
    else if (expand(t, null).trim() !== '') fatal('missing separator');
  }
  closeRule();
  if (blocks.length > 0) {
    curLine = blocks[blocks.length - 1].line;
    fatal("missing 'endif'");
  }
}

// ---------- rule resolution ----------
function canMake(name: string, depth: number): boolean {
  if (table.has(name) || explicit.has(name) || phony.has(name)) return true;
  if (depth <= 0) return false;
  return findPattern(name, depth - 1) !== null;
}

function findPattern(t: string, depth: number): { rule: PatRule; stem: string } | null {
  for (const pr of patterns) {
    if (pr.recipe.length === 0) continue;
    const stem = matchPat(pr.pattern, t);
    if (!stem) continue;
    let ok = true;
    for (const p of pr.normal.concat(pr.oo)) {
      if (!canMake(replaceFirst(p, '%', stem), depth)) {
        ok = false;
        break;
      }
    }
    if (ok) return { rule: pr, stem };
  }
  return null;
}

function resolve(t: string): Rule | null {
  const e = explicit.get(t);
  if (e && e.recipe.length > 0) return { normal: e.normal, oo: e.oo, recipe: e.recipe, stem: '' };
  const pm = findPattern(t, 8);
  if (pm) {
    const sub = (p: string): string => replaceFirst(p, '%', pm.stem);
    return {
      normal: pm.rule.normal.map(sub).concat(e ? e.normal : []),
      oo: pm.rule.oo.map(sub).concat(e ? e.oo : []),
      recipe: pm.rule.recipe,
      stem: pm.stem,
    };
  }
  if (e) return { normal: e.normal, oo: e.oo, recipe: [], stem: '' };
  return null;
}

function defaultGoal(): string | null {
  for (const n of explicitOrder) if (!n.startsWith('.')) return n;
  return null;
}

// ---------- simulated execution ----------
function tick(): number {
  return ++clock;
}

function simulate(cmd: string): number {
  const w = cmd.split(/\s+/);
  const name = w[0];
  const args = w.slice(1);
  switch (name) {
    case 'false':
      return 1;
    case 'exit':
      if (args.length === 0) return 0;
      return /^[+-]?\d+$/.test(args[0]) ? Number(args[0]) : 2;
    case 'touch':
      for (const a of args) if (!a.startsWith('-')) table.set(a, tick());
      return 0;
    case 'rm':
      for (const a of args) if (!a.startsWith('-')) table.delete(a);
      return 0;
    case 'cp': {
      if (args.length !== 2) return 0;
      const [src, dst] = args;
      if (!table.has(src)) {
        out.push(`cp: cannot stat '${src}': No such file or directory`);
        return 1;
      }
      table.set(dst, tick());
      return 0;
    }
    case 'echo':
      out.push(args.map((a) => a.replace(/['"]/g, '')).join(' '));
      return 0;
    default:
      return 0;
  }
}

function runRecipe(
  t: string,
  rule: Rule,
  wasIn: boolean,
  oldM: number | undefined,
  results: Map<string, boolean>,
): void {
  recipeCount++;
  const deps = dedupe(rule.normal);
  const qlist = deps.filter(
    (p) =>
      !wasIn ||
      results.get(p) === true ||
      (table.has(p) && oldM !== undefined && (table.get(p) as number) > oldM),
  );
  const auto: Record<string, string> = {
    '@': t,
    '<': rule.normal[0] ?? '',
    '^': deps.join(' '),
    '?': qlist.join(' '),
    '|': dedupe(rule.oo).join(' '),
    '*': rule.stem,
  };
  for (const rl of rule.recipe) {
    curLine = rl.line;
    let s = expand(rl.text, auto).trim();
    let silent = false;
    let ignore = false;
    while (s.length > 0 && /[ \t@\-+]/.test(s[0])) {
      if (s[0] === '@') silent = true;
      else if (s[0] === '-') ignore = true;
      s = s.slice(1);
    }
    const cmd = s.trim();
    if (cmd === '') continue;
    if (dryMode) {
      out.push(cmd);
      continue;
    }
    if (!silent) out.push(cmd);
    const status = simulate(cmd);
    if (status !== 0) {
      if (ignore) {
        out.push(`make: [Makefile:${rl.line}: ${t}] Error ${status} (ignored)`);
      } else {
        stopWith(`make: *** [Makefile:${rl.line}: ${t}] Error ${status}`);
      }
    }
  }
  curLine = null;
  if (!dryMode && !phony.has(t)) table.set(t, tick());
}

// update(T, neededBy): returns whether T changed.
function update(t: string, neededBy: string | null): boolean {
  const m = memo.get(t);
  if (m !== undefined) return m;
  const idx = stack.indexOf(t);
  if (idx >= 0) {
    stopWith(`make: *** Circular dependency detected: ${stack.slice(idx).concat([t]).join(' -> ')}.  Stop.`);
  }
  const rule = resolve(t);
  if (rule === null) {
    if (table.has(t)) {
      memo.set(t, false);
      return false;
    }
    if (phony.has(t)) {
      memo.set(t, true);
      return true;
    }
    stopWith(
      neededBy === null
        ? `make: *** No rule to make target '${t}'.  Stop.`
        : `make: *** No rule to make target '${t}', needed by '${neededBy}'.  Stop.`,
    );
  }
  const wasIn = table.has(t);
  const oldM = table.get(t);
  stack.push(t);
  const normal = dedupe(rule.normal);
  const results = new Map<string, boolean>();
  let anyChanged = false;
  for (const p of normal) {
    const c = update(p, t);
    results.set(p, c);
    if (c) anyChanged = true;
  }
  let newer = false;
  if (wasIn) {
    for (const p of normal) {
      const pm = table.get(p);
      if (pm !== undefined && pm > (oldM as number)) newer = true;
    }
  }
  for (const o of dedupe(rule.oo)) update(o, t);
  stack.pop();

  const must = phony.has(t) || !table.has(t) || anyChanged || newer;
  let changed = false;
  if (must) {
    changed = true;
    if (rule.recipe.length > 0) runRecipe(t, rule, wasIn, oldM, results);
  }
  memo.set(t, changed);
  return changed;
}

// ---------- requests ----------
function setupParse(args: string[]): string[] {
  const goals: string[] = [];
  const cli = new Map<string, string>();
  for (const a of args) {
    const eq = a.indexOf('=');
    if (eq > 0) cli.set(a.slice(0, eq), a.slice(eq + 1));
    else goals.push(a);
  }
  vars = new Map();
  for (const [k, v] of cli) vars.set(k, { rec: true, value: v, cli: true });
  parseMakefile();
  return goals;
}

function runBuild(args: string[], isDry: boolean): void {
  let goals = setupParse(args);
  if (goals.length === 0) {
    const d = defaultGoal();
    if (d === null) {
      out.push('make: *** No targets.  Stop.');
      return;
    }
    goals = [d];
  }
  dryMode = isDry;
  memo = new Map();
  stack = [];
  for (const g of goals) {
    const before = recipeCount;
    update(g, null);
    if (recipeCount === before) {
      const r = resolve(g);
      if ((r !== null && r.recipe.length > 0) || (!phony.has(g) && table.has(g))) {
        out.push(`make: '${g}' is up to date.`);
      } else {
        out.push(`make: Nothing to be done for '${g}'.`);
      }
    }
  }
}

function depsOf(target: string): string[] {
  const res: string[] = [];
  const visited = new Set<string>();
  const path = [target];
  const visit = (x: string): void => {
    const r = resolve(x);
    if (!r) return;
    for (const p of dedupe(r.normal).concat(dedupe(r.oo))) {
      const idx = path.indexOf(p);
      if (idx >= 0) {
        stopWith(`make: *** Circular dependency detected: ${path.slice(idx).concat([p]).join(' -> ')}.  Stop.`);
      }
      if (visited.has(p)) continue;
      visited.add(p);
      path.push(p);
      visit(p);
      path.pop();
      res.push(p);
    }
  };
  visit(target);
  return res;
}

function fmtRule(head: string, normal: string[], oo: string[]): string {
  let s = head + ':';
  if (normal.length) s += ' ' + normal.join(' ');
  if (oo.length) s += ' | ' + oo.join(' ');
  return s;
}

function handle(line: string): void {
  const t = line.trim();
  const w = t.split(/\s+/);
  const cmd = w[0];
  const args = w.slice(1);
  switch (cmd) {
    case 'build':
      runBuild(args, false);
      break;
    case 'dry':
      runBuild(args, true);
      break;
    case 'deps': {
      const goals = setupParse(args);
      if (goals.length !== 1) {
        out.push('usage: deps TARGET');
        break;
      }
      const list = depsOf(goals[0]);
      if (list.length === 0) out.push('(no prerequisites)');
      else for (const p of list) out.push(p);
      break;
    }
    case 'targets': {
      setupParse(args);
      const d = defaultGoal();
      if (d !== null) out.push(`default: ${d}`);
      for (const name of explicitOrder) {
        const e = explicit.get(name) as Entry;
        out.push(fmtRule(name, e.normal, e.oo));
      }
      for (const p of patterns) out.push(fmtRule(`pattern ${p.pattern}`, p.normal, p.oo));
      if (phonyOrder.length) out.push('phony: ' + phonyOrder.join(' '));
      break;
    }
    case 'expand': {
      const text = t.slice(cmd.length).trim();
      setupParse([]);
      curLine = null;
      out.push(`[${expand(text, null)}]`);
      break;
    }
    case 'files': {
      const names = [...table.keys()].sort(byteCmp);
      if (names.length === 0) out.push('(no files)');
      else for (const n of names) out.push(`${n} ${table.get(n)}`);
      break;
    }
    case 'touch': {
      if (args.length === 1) {
        table.set(args[0], tick());
      } else if (args.length === 2 && /^-?\d+$/.test(args[1])) {
        const n = Number(args[1]);
        table.set(args[0], n);
        if (n > clock) clock = n;
      } else {
        out.push('bad request');
      }
      break;
    }
    case 'rm':
      for (const a of args) table.delete(a);
      break;
    default:
      out.push(`unknown request: ${cmd}`);
  }
}

function main(): void {
  const input = fs.readFileSync(0, 'utf8');
  const lines = input.split('\n').map((l) => (l.endsWith('\r') ? l.slice(0, -1) : l));
  const seps: number[] = [];
  for (let i = 0; i < lines.length && seps.length < 2; i++) {
    if (lines[i] === '====') seps.push(i);
  }
  const s1 = seps.length > 0 ? seps[0] : lines.length;
  const s2 = seps.length > 1 ? seps[1] : lines.length;
  makeLines = lines.slice(0, s1);
  const tableLines = s1 < lines.length ? lines.slice(s1 + 1, s2) : [];
  const reqLines = s2 < lines.length ? lines.slice(s2 + 1) : [];

  for (const l of tableLines) {
    const f = l.trim() === '' ? [] : l.trim().split(/\s+/);
    if (f.length === 2 && /^\d+$/.test(f[1])) table.set(f[0], Number(f[1]));
  }
  for (const v of table.values()) if (v > clock) clock = v;

  try {
    for (const req of reqLines) {
      const t = req.trim();
      if (t === '' || t.startsWith('#')) continue;
      out.push('> ' + req.trimEnd());
      bindings = new Map();
      expStack = [];
      curLine = null;
      try {
        handle(req);
      } catch (e) {
        if (!(e instanceof Stop)) throw e;
      }
    }
  } finally {
    if (out.length > 0) process.stdout.write(out.join('\n') + '\n');
  }
}

main();
