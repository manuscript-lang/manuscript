// Read stdin, write stdout. See TASK.md.
import { readFileSync } from 'node:fs';

// ---------------------------------------------------------------- errors & output

class CmdError extends Error {}

function fail(msg: string): never {
  throw new CmdError(msg);
}

const out: string[] = [];
function emit(s: string): void {
  out.push(s);
}

// ---------------------------------------------------------------- model

interface Comment {
  t: number;
  actor: string;
  text: string;
}

interface Issue {
  id: number;
  title: string;
  state: string;
  priority: string;
  assignee: string | null;
  reporter: string | null;
  points: number | null;
  due: string | null;
  labels: string[];
  comments: Comment[];
  created: number;
  updated: number;
}

type Patch = Partial<Issue>;

interface Entry {
  t: number;
  actor: string;
  id: number;
  detail: string;
}

interface Transition {
  to: string;
  guards: string[];
}

interface Workflow {
  initial: string;
  states: string[];
  stateIdx: Map<string, number>;
  finals: Set<string>;
  trans: Map<string, Transition[]>;
}

type Pred = (i: Issue) => boolean;

interface SortKey {
  name: string;
  desc: boolean;
}

let clock = 0;
let actor = 'system';
let today = '1970-01-01';
let nextId = 1;
let wf: Workflow | null = null;
const issues = new Map<number, Issue>();
const log: Entry[] = [];
const views = new Map<string, string>();

const PRIO = ['low', 'medium', 'high', 'critical'];
const RANK: Record<string, number> = { low: 0, medium: 1, high: 2, critical: 3 };
const FIELDS = ['title', 'priority', 'assignee', 'points', 'due', 'labels', 'reporter'];
const GUARDS = ['assignee', 'points', 'due', 'labels', 'reporter'];
const STATE_RE = /^[a-z][a-z0-9_]*$/;
const LABEL_RE = /^[a-z0-9_-]+$/;
const VIEW_RE = /^[a-z][a-z0-9_-]*$/;
const SORT_FIELDS = ['id', 'created', 'updated', 'priority', 'points', 'state', 'title', 'assignee', 'reporter', 'due'];

function isFinal(i: Issue): boolean {
  return wf !== null && wf.finals.has(i.state);
}

function isOverdue(i: Issue): boolean {
  return !isFinal(i) && i.due !== null && i.due < today;
}

function addLog(id: number, detail: string): void {
  log.push({ t: clock, actor, id, detail });
}

// ---------------------------------------------------------------- lexing helpers

interface Ch {
  c: string;
  q: boolean;
}

interface Word {
  chars: Ch[];
  raw: string;
}

function isSpace(ch: string): boolean {
  return /\s/.test(ch);
}

// Scans one word starting at `start`. A double quote opens a quoted section
// (inside a word); `\"` and `\\` inside quotes are escapes. Outside quotes a
// backslash is literal. In filter mode parentheses end a word.
function scanWord(text: string, start: number, parens: boolean, errPrefix: string): { word: Word; end: number } {
  const chars: Ch[] = [];
  let i = start;
  while (i < text.length) {
    const ch = text[i];
    if (isSpace(ch)) break;
    if (parens && (ch === '(' || ch === ')')) break;
    if (ch === '"') {
      i++;
      let closed = false;
      while (i < text.length) {
        const d = text[i];
        if (d === '"') {
          closed = true;
          i++;
          break;
        }
        if (d === '\\' && i + 1 < text.length && (text[i + 1] === '"' || text[i + 1] === '\\')) {
          chars.push({ c: text[i + 1], q: true });
          i += 2;
          continue;
        }
        chars.push({ c: d, q: true });
        i++;
      }
      if (!closed) fail(errPrefix + 'unterminated quote');
    } else {
      chars.push({ c: ch, q: false });
      i++;
    }
  }
  return { word: { chars, raw: text.slice(start, i) }, end: i };
}

// Token style: split on whitespace, quotes group inside a token.
function tokenize(text: string): string[] {
  const res: string[] = [];
  let i = 0;
  while (i < text.length) {
    if (isSpace(text[i])) {
      i++;
      continue;
    }
    const { word, end } = scanWord(text, i, false, '');
    res.push(word.chars.map((x) => x.c).join(''));
    i = end;
  }
  return res;
}

// Word style: split on spaces and tabs.
function words(s: string): string[] {
  return s.split(/[ \t]+/).filter((x) => x !== '');
}

// First word and the remainder (leading separators removed, otherwise verbatim).
function nextWord(s: string): [string, string] {
  const t = s.replace(/^[ \t]+/, '');
  const m = t.search(/[ \t]/);
  if (m < 0) return [t, ''];
  return [t.slice(0, m), t.slice(m).replace(/^[ \t]+/, '')];
}

// ---------------------------------------------------------------- value rules

function isLeap(y: number): boolean {
  return (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0;
}

function validDate(s: string): boolean {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!m) return false;
  const y = Number(m[1]);
  const mo = Number(m[2]);
  const d = Number(m[3]);
  if (y < 1 || mo < 1 || mo > 12 || d < 1) return false;
  const dim = [31, isLeap(y) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][mo - 1];
  return d <= dim;
}

function parseIntStrict(s: string): number | null {
  if (!/^(0|[1-9]\d*)$/.test(s)) return null;
  const n = Number(s);
  return n <= 1000000 ? n : null;
}

function parseId(tok: string): number {
  const m = /^#?(\d+)$/.exec(tok);
  if (!m) fail(`bad issue id '${tok}'`);
  const n = Number(m[1]);
  if (n < 1) fail(`bad issue id '${tok}'`);
  return n;
}

function liveIssue(id: number): Issue {
  const i = issues.get(id);
  if (!i) fail(`no such issue #${id}`);
  return i;
}

function getField(i: Issue, f: string): unknown {
  return (i as unknown as Record<string, unknown>)[f];
}

function fmtVal(field: string, v: unknown): string {
  if (field === 'labels') {
    const a = v as string[];
    return a.length ? a.join(',') : '-';
  }
  if (v === null || v === undefined || v === '') return '-';
  return String(v);
}

function sameVal(field: string, a: unknown, b: unknown): boolean {
  if (field === 'labels') return (a as string[]).join(',') === (b as string[]).join(',');
  return a === b;
}

// Parses one field=value token (create/edit/assign/bulk set).
function parseAssignment(tok: string): Patch {
  const eq = tok.indexOf('=');
  if (eq <= 0) fail(`expected field=value, got '${tok}'`);
  const field = tok.slice(0, eq);
  const value = tok.slice(eq + 1);
  if (field === 'state') fail('use move to change state');
  if (!FIELDS.includes(field)) fail(`unknown field '${field}'`);
  switch (field) {
    case 'title':
      if (value.trim() === '') fail('empty title');
      return { title: value };
    case 'priority':
      if (!PRIO.includes(value)) fail(`bad priority '${value}'`);
      return { priority: value };
    case 'assignee':
      if (value === 'none') return { assignee: null };
      if (value.trim() === '') fail('empty assignee');
      return { assignee: value };
    case 'reporter':
      if (value === 'none') return { reporter: null };
      if (value.trim() === '') fail('empty reporter');
      return { reporter: value };
    case 'points': {
      if (value === 'none') return { points: null };
      const n = parseIntStrict(value);
      if (n === null) fail(`bad points '${value}'`);
      return { points: n };
    }
    case 'due':
      if (value === 'none') return { due: null };
      if (!validDate(value)) fail(`bad date '${value}'`);
      return { due: value };
    case 'labels': {
      if (value === 'none') return { labels: [] };
      const set = new Set<string>();
      for (const part of value.split(',')) {
        const l = part.toLowerCase();
        if (!LABEL_RE.test(l)) fail(`bad label '${l}'`);
        set.add(l);
      }
      return { labels: [...set].sort() };
    }
  }
  return {};
}

// ---------------------------------------------------------------- workflow

function guardUnmet(iss: Issue, g: string): boolean {
  switch (g) {
    case 'assignee':
      return iss.assignee === null;
    case 'points':
      return iss.points === null;
    case 'due':
      return iss.due === null;
    case 'labels':
      return iss.labels.length === 0;
    case 'reporter':
      return iss.reporter === null;
  }
  return false;
}

function defineWorkflow(body: string[]): void {
  if (nextId > 1) fail('workflow: cannot redefine after issues were created');
  let initial: string | null = null;
  const states: string[] = [];
  const stateIdx = new Map<string, number>();
  const addState = (n: string): void => {
    if (!stateIdx.has(n)) {
      stateIdx.set(n, states.length);
      states.push(n);
    }
  };
  const finals = new Set<string>();
  const trans = new Map<string, Transition[]>();
  const srcs: string[] = [];
  let count = 0;

  for (const raw of body) {
    const line = raw.trim();
    if (line === '' || line.startsWith('#')) continue;
    if (line.startsWith('initial:')) {
      const name = line.slice('initial:'.length).trim();
      if (!STATE_RE.test(name)) fail(`workflow: bad state name '${name}'`);
      if (initial !== null) fail('workflow: initial state defined twice');
      initial = name;
      addState(name);
    } else if (line.startsWith('final:')) {
      for (const part of line.slice('final:'.length).split(',')) {
        const name = part.trim();
        if (!STATE_RE.test(name)) fail(`workflow: bad state name '${name}'`);
        addState(name);
        finals.add(name);
      }
    } else if (line.includes('->')) {
      const k = line.indexOf('->');
      const src = line.slice(0, k).trim();
      if (!STATE_RE.test(src)) fail(`workflow: bad state name '${src}'`);
      addState(src);
      for (const ent of line.slice(k + 2).split(',')) {
        const e = ent.trim();
        const parts = e === '' ? [] : e.split(/\s+/);
        let to = '';
        let guards: string[] = [];
        if (parts.length === 1) {
          to = parts[0];
        } else if (parts.length === 3 && parts[1] === 'requires') {
          to = parts[0];
          guards = parts[2].split('+');
        } else {
          fail(`workflow: bad line '${line}'`);
        }
        if (!STATE_RE.test(to)) fail(`workflow: bad state name '${to}'`);
        for (const g of guards) {
          if (!GUARDS.includes(g)) fail(`workflow: bad guard field '${g}'`);
        }
        addState(to);
        const arr = trans.get(src) ?? [];
        arr.push({ to, guards });
        trans.set(src, arr);
        count++;
      }
      srcs.push(src);
    } else {
      fail(`workflow: bad line '${line}'`);
    }
  }

  if (initial === null) fail('workflow: initial state missing');
  for (const s of srcs) {
    if (finals.has(s)) fail(`workflow: '${s}' is final and cannot have transitions`);
  }
  wf = { initial, states, stateIdx, finals, trans };
  emit(`workflow ok: ${states.length} states, ${count} transitions`);
}

// ---------------------------------------------------------------- issue commands

function commit(iss: Issue, patch: Patch): void {
  const old = { ...iss };
  const next = { ...iss, ...patch } as Issue;
  const changed = FIELDS.filter((f) => !sameVal(f, getField(old, f), getField(next, f)));
  if (changed.length === 0) {
    emit(`#${iss.id} unchanged`);
    return;
  }
  clock++;
  Object.assign(iss, patch);
  iss.updated = clock;
  for (const f of changed) {
    addLog(iss.id, `${f}: ${fmtVal(f, getField(old, f))} -> ${fmtVal(f, getField(iss, f))}`);
  }
  emit(`updated #${iss.id}`);
}

function doEdit(idTok: string, fieldToks: string[]): void {
  const id = parseId(idTok);
  const iss = liveIssue(id);
  if (isFinal(iss)) fail(`#${id} is in final state '${iss.state}'`);
  const patch: Patch = {};
  for (const t of fieldToks) Object.assign(patch, parseAssignment(t));
  if (fieldToks.length === 0) fail('usage: edit ID field=value...');
  commit(iss, patch);
}

function cmdCreate(rest: string): void {
  if (wf === null) fail('no workflow defined');
  const toks = tokenize(rest);
  if (toks.length === 0) fail('usage: create TITLE [field=value...]');
  const title = toks[0];
  if (title.trim() === '') fail('empty title');
  const patch: Patch = {};
  for (const t of toks.slice(1)) Object.assign(patch, parseAssignment(t));

  const id = nextId++;
  clock++;
  const defaults: Issue = {
    id,
    title,
    state: wf.initial,
    priority: 'medium',
    assignee: null,
    reporter: actor,
    points: null,
    due: null,
    labels: [],
    comments: [],
    created: clock,
    updated: clock,
  };
  const iss = { ...defaults, ...patch } as Issue;
  addLog(id, `created "${title}"`);
  for (const f of FIELDS) {
    if (!sameVal(f, getField(defaults, f), getField(iss, f))) {
      addLog(id, `${f}: ${fmtVal(f, getField(defaults, f))} -> ${fmtVal(f, getField(iss, f))}`);
    }
  }
  issues.set(id, iss);
  emit(`created #${id}`);
}

function cmdEdit(rest: string): void {
  const toks = tokenize(rest);
  if (toks.length === 0) fail('usage: edit ID field=value...');
  doEdit(toks[0], toks.slice(1));
}

function cmdAssign(rest: string): void {
  const toks = tokenize(rest);
  if (toks.length !== 2) fail('usage: assign ID NAME');
  doEdit(toks[0], ['assignee=' + toks[1]]);
}

function doLabel(idTok: string, opToks: string[]): void {
  const id = parseId(idTok);
  const iss = liveIssue(id);
  if (isFinal(iss)) fail(`#${id} is in final state '${iss.state}'`);
  const ops = opToks.map((t) => {
    let sign = '+';
    let name = t;
    if (t[0] === '+' || t[0] === '-') {
      sign = t[0];
      name = t.slice(1);
    }
    const l = name.toLowerCase();
    if (!LABEL_RE.test(l)) fail(`bad label '${l}'`);
    return { sign, l };
  });
  const set = new Set(iss.labels);
  for (const op of ops) {
    if (op.sign === '-') set.delete(op.l);
    else set.add(op.l);
  }
  commit(iss, { labels: [...set].sort() });
}

function cmdLabel(rest: string): void {
  const toks = tokenize(rest);
  if (toks.length < 2) fail('usage: label ID +label -label...');
  doLabel(toks[0], toks.slice(1));
}

function doMove(idTok: string, to: string, comment: string | null): void {
  const id = parseId(idTok);
  const iss = liveIssue(id);
  if (isFinal(iss)) fail(`#${id} is in final state '${iss.state}'`);
  const w = wf as Workflow;
  if (!w.stateIdx.has(to)) fail(`unknown state '${to}'`);
  const from = iss.state;
  if (from === to) fail(`already in state '${to}'`);
  const tr = (w.trans.get(from) ?? []).find((x) => x.to === to);
  if (!tr) fail(`transition '${from} -> ${to}' not allowed`);
  const missing = tr.guards.filter((g) => guardUnmet(iss, g));
  if (missing.length > 0) fail(`cannot move #${id} to ${to}: missing ${missing.join(', ')}`);
  clock++;
  iss.state = to;
  iss.updated = clock;
  addLog(id, `state: ${from} -> ${to}`);
  if (comment !== null) {
    iss.comments.push({ t: clock, actor, text: comment });
    addLog(id, `comment: ${comment}`);
  }
  emit(`moved #${id}: ${from} -> ${to}`);
}

function cmdMove(rest: string): void {
  const [idTok, r1] = nextWord(rest);
  const [to, comment] = nextWord(r1);
  if (idTok === '' || to === '') fail('usage: move ID STATE [comment...]');
  doMove(idTok, to, comment === '' ? null : comment);
}

function cmdComment(rest: string): void {
  const [idTok, text] = nextWord(rest);
  if (idTok === '' || text === '') fail('usage: comment ID TEXT');
  const id = parseId(idTok);
  const iss = liveIssue(id);
  clock++;
  iss.comments.push({ t: clock, actor, text });
  iss.updated = clock;
  addLog(id, `comment: ${text}`);
  emit(`commented #${id}`);
}

function cmdDelete(rest: string): void {
  const w = words(rest);
  if (w.length !== 1) fail('usage: delete ID');
  const id = parseId(w[0]);
  liveIssue(id);
  clock++;
  issues.delete(id);
  addLog(id, 'deleted');
  emit(`deleted #${id}`);
}

function cmdShow(rest: string): void {
  const w = words(rest);
  if (w.length !== 1) fail('usage: show ID');
  const iss = liveIssue(parseId(w[0]));
  emit(`#${iss.id} ${iss.title}`);
  emit(`  state: ${iss.state}`);
  emit(`  priority: ${iss.priority}`);
  emit(`  assignee: ${fmtVal('assignee', iss.assignee)}`);
  emit(`  points: ${fmtVal('points', iss.points)}`);
  emit(`  due: ${fmtVal('due', iss.due)}`);
  emit(`  labels: ${iss.labels.length ? iss.labels.join(', ') : '-'}`);
  emit(`  reporter: ${fmtVal('reporter', iss.reporter)}`);
  emit(`  created: t=${iss.created}, updated: t=${iss.updated}`);
  emit(`  comments: ${iss.comments.length}`);
  for (const c of iss.comments) emit(`    [t=${c.t} ${c.actor}] ${c.text}`);
}

function cmdLog(rest: string): void {
  const a = words(rest);
  let idTok: string | null = null;
  let i = 0;
  if (a.length > 0 && a[0] !== 'tail') {
    idTok = a[0];
    i = 1;
  }
  const remain = a.length - i;
  let tailTok: string | null = null;
  if (remain === 2 && a[i] === 'tail') tailTok = a[i + 1];
  else if (remain !== 0) fail('usage: log [ID] [tail N]');
  let id: number | null = null;
  if (idTok !== null) {
    id = parseId(idTok);
    if (id >= nextId) fail(`no such issue #${id}`);
  }
  let tail: number | null = null;
  if (tailTok !== null) {
    tail = parseIntStrict(tailTok);
    if (tail === null) fail(`bad tail '${tailTok}'`);
  }
  let sel = log.filter((e) => id === null || e.id === id);
  if (tail !== null) sel = sel.slice(Math.max(0, sel.length - tail));
  if (sel.length === 0) emit('(no log entries)');
  for (const e of sel) emit(`t=${e.t} ${e.actor} #${e.id} ${e.detail}`);
}

// ---------------------------------------------------------------- filter language

const CMP_OPS = [':', '!=', '<', '<=', '>', '>='];
const TEXT_OPS = [':', '!=', '~'];
const ORD_OPS = ['<', '<=', '>', '>='];
const FIELD_OPS = new Map<string, string[]>([
  ['id', CMP_OPS],
  ['created', CMP_OPS],
  ['updated', CMP_OPS],
  ['points', CMP_OPS],
  ['priority', CMP_OPS],
  ['due', CMP_OPS],
  ['title', TEXT_OPS],
  ['assignee', TEXT_OPS],
  ['reporter', TEXT_OPS],
  ['text', ['~']],
  ['state', [':', '!=']],
  ['label', TEXT_OPS],
  ['labels', TEXT_OPS],
  ['is', [':']],
  ['has', [':']],
  ['view', [':']],
]);

interface FTok {
  kind: 'word' | 'op' | 'paren';
  raw: string;
  v: string;
  word?: Word;
}

function lexFilter(text: string): FTok[] {
  const toks: FTok[] = [];
  let i = 0;
  while (i < text.length) {
    const ch = text[i];
    if (isSpace(ch)) {
      i++;
      continue;
    }
    if (ch === '(' || ch === ')') {
      toks.push({ kind: 'paren', raw: ch, v: ch });
      i++;
      continue;
    }
    const { word, end } = scanWord(text, i, true, 'query: ');
    i = end;
    if (word.raw === 'AND' || word.raw === 'OR' || word.raw === 'NOT') {
      toks.push({ kind: 'op', raw: word.raw, v: word.raw });
    } else {
      toks.push({ kind: 'word', raw: word.raw, v: '', word });
    }
  }
  return toks;
}

// Splits unquoted `|` into alternatives. Without an unquoted `|` the result is [whole].
function splitAlts(segs: Ch[]): string[] {
  const res: string[] = [];
  let cur = '';
  for (const s of segs) {
    if (!s.q && s.c === '|') {
      res.push(cur);
      cur = '';
    } else {
      cur += s.c;
    }
  }
  res.push(cur);
  return res;
}

function cmpOp(op: string, x: number, n: number): boolean {
  switch (op) {
    case '<':
      return x < n;
    case '<=':
      return x <= n;
    case '>':
      return x > n;
    case '>=':
      return x >= n;
  }
  return false;
}

function strCmp(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

function ciCmp(a: string, b: string): number {
  return strCmp(a.toLowerCase(), b.toLowerCase());
}

function cmpOpt<T>(x: T | null, y: T | null, c: (a: T, b: T) => number): number {
  if (x === null && y === null) return 0;
  if (x === null) return 1;
  if (y === null) return -1;
  return c(x, y);
}

function negIf(op: string, any: Pred): Pred {
  return op === '!=' ? (i) => !any(i) : any;
}

function numPred(
  field: string,
  op: string,
  alts: string[],
  whole: string,
  get: (i: Issue) => number | null,
  allowNone: boolean,
): Pred {
  const bad = (v: string): never => fail(`query: bad value '${v}' for field '${field}'`);
  if (ORD_OPS.includes(op)) {
    const n = parseIntStrict(whole);
    if (n === null) bad(whole);
    return (i) => {
      const x = get(i);
      return x !== null && cmpOp(op, x, n);
    };
  }
  const tests: Pred[] = alts.map((a) => {
    if (allowNone && a === 'none') return (i: Issue) => get(i) === null;
    const n = parseIntStrict(a);
    if (n === null) bad(a);
    return (i: Issue) => get(i) === n;
  });
  return negIf(op, (i) => tests.some((t) => t(i)));
}

function dateOrNoneTerm(field: string, op: string, alts: string[], whole: string, get: (i: Issue) => string | null): Pred {
  const bad = (v: string): never => fail(`query: bad value '${v}' for field '${field}'`);
  if (ORD_OPS.includes(op)) {
    if (!validDate(whole)) bad(whole);
    return (i) => {
      const x = get(i);
      if (x === null) return false;
      switch (op) {
        case '<':
          return x < whole;
        case '<=':
          return x <= whole;
        case '>':
          return x > whole;
        default:
          return x >= whole;
      }
    };
  }
  const tests: Pred[] = alts.map((a) => {
    if (a === 'none') return (i: Issue) => get(i) === null;
    if (!validDate(a)) bad(a);
    return (i: Issue) => get(i) === a;
  });
  return negIf(op, (i) => tests.some((t) => t(i)));
}

function textTerm(op: string, alts: string[], get: (i: Issue) => string | null): Pred {
  if (op === '~') {
    const subs = alts.map((a) => a.toLowerCase());
    return (i) => {
      const x = get(i);
      if (x === null) return false;
      const lx = x.toLowerCase();
      return subs.some((s) => lx.includes(s));
    };
  }
  const tests: Pred[] = alts.map((a) => {
    if (a === 'none') return (i: Issue) => get(i) === null;
    const la = a.toLowerCase();
    return (i: Issue) => {
      const x = get(i);
      return x !== null && x.toLowerCase() === la;
    };
  });
  return negIf(op, (i) => tests.some((t) => t(i)));
}

function labelTerm(op: string, alts: string[]): Pred {
  const labs = alts.map((a) => a.toLowerCase());
  if (op === '~') {
    return (i) => i.labels.some((l) => labs.some((s) => l.includes(s)));
  }
  const tests: Pred[] = labs.map((a) => {
    if (a === 'none') return (i: Issue) => i.labels.length === 0;
    return (i: Issue) => i.labels.includes(a);
  });
  return negIf(op, (i) => tests.some((t) => t(i)));
}

function parseFilter(text: string, refs: string[] = []): Pred | null {
  if (text.trim() === '') return null;
  const toks = lexFilter(text);
  let p = 0;

  const isOp = (t: FTok | undefined, v: string): boolean => t !== undefined && t.kind === 'op' && t.v === v;
  const need = (): FTok => {
    if (p >= toks.length) fail('query: unexpected end of query');
    return toks[p];
  };

  function parseOr(): Pred {
    let l = parseAnd();
    while (isOp(toks[p], 'OR')) {
      p++;
      const a = l;
      const r = parseAnd();
      l = (i) => a(i) || r(i);
    }
    return l;
  }

  function parseAnd(): Pred {
    let l = parseNot();
    for (;;) {
      const t = toks[p];
      if (isOp(t, 'AND')) {
        p++;
        const a = l;
        const r = parseNot();
        l = (i) => a(i) && r(i);
      } else if (t !== undefined && (t.kind === 'word' || isOp(t, 'NOT') || (t.kind === 'paren' && t.v === '('))) {
        const a = l;
        const r = parseNot();
        l = (i) => a(i) && r(i);
      } else {
        break;
      }
    }
    return l;
  }

  function parseNot(): Pred {
    const t = need();
    if (isOp(t, 'NOT')) {
      p++;
      const a = parseNot();
      return (i) => !a(i);
    }
    return parsePrimary();
  }

  function parsePrimary(): Pred {
    const t = need();
    if (t.kind === 'paren' && t.v === '(') {
      p++;
      const e = parseOr();
      const c = need();
      if (c.kind === 'paren' && c.v === ')') {
        p++;
        return e;
      }
      fail(`query: unexpected token '${c.raw}'`);
    }
    if (t.kind === 'word' && t.word) {
      p++;
      return parseTerm(t.word, refs);
    }
    fail(`query: unexpected token '${t.raw}'`);
  }

  const e = parseOr();
  if (p < toks.length) fail(`query: unexpected token '${toks[p].raw}'`);
  return e;
}

function parseTerm(w: Word, refs: string[]): Pred {
  const s = w.chars.map((x) => x.c).join('');
  const m = /^([a-z_]+)(!=|<=|>=|:|<|>|~)/.exec(s);
  if (!m) fail(`query: unexpected token '${w.raw}'`);
  const field = m[1];
  const op = m[2];
  const segs = w.chars.slice(m[0].length);
  const ops = FIELD_OPS.get(field);
  if (!ops) fail(`query: unknown field '${field}'`);
  if (!ops.includes(op)) fail(`query: bad operator '${op}' for field '${field}'`);
  const whole = segs.map((x) => x.c).join('');
  const noSplit = field === 'view' || ORD_OPS.includes(op);
  const alts = noSplit ? [whole] : splitAlts(segs);
  const bad = (v: string): never => fail(`query: bad value '${v}' for field '${field}'`);

  switch (field) {
    case 'id':
      return numPred(field, op, alts, whole, (i) => i.id, false);
    case 'created':
      return numPred(field, op, alts, whole, (i) => i.created, false);
    case 'updated':
      return numPred(field, op, alts, whole, (i) => i.updated, false);
    case 'points':
      return numPred(field, op, alts, whole, (i) => i.points, true);
    case 'due':
      return dateOrNoneTerm(field, op, alts, whole, (i) => i.due);
    case 'title':
      return textTerm(op, alts, (i) => i.title);
    case 'assignee':
      return textTerm(op, alts, (i) => i.assignee);
    case 'reporter':
      return textTerm(op, alts, (i) => i.reporter);
    case 'text': {
      const subs = alts.map((a) => a.toLowerCase());
      return (i) => {
        const t = i.title.toLowerCase();
        return subs.some((x) => t.includes(x) || i.comments.some((c) => c.text.toLowerCase().includes(x)));
      };
    }
    case 'state': {
      const tests: Pred[] = alts.map((a) => {
        if (wf === null || !wf.stateIdx.has(a)) bad(a);
        return (i: Issue) => i.state === a;
      });
      return negIf(op, (i) => tests.some((t) => t(i)));
    }
    case 'priority': {
      if (ORD_OPS.includes(op)) {
        if (!PRIO.includes(whole)) bad(whole);
        const r = RANK[whole];
        return (i) => cmpOp(op, RANK[i.priority], r);
      }
      const tests: Pred[] = alts.map((a) => {
        if (!PRIO.includes(a)) bad(a);
        return (i: Issue) => i.priority === a;
      });
      return negIf(op, (i) => tests.some((t) => t(i)));
    }
    case 'label':
    case 'labels':
      return labelTerm(op, alts);
    case 'is': {
      const tests: Pred[] = alts.map((a) => {
        switch (a) {
          case 'open':
            return (i: Issue) => !isFinal(i);
          case 'final':
            return (i: Issue) => isFinal(i);
          case 'overdue':
            return (i: Issue) => isOverdue(i);
          case 'unassigned':
            return (i: Issue) => i.assignee === null;
        }
        return bad(a);
      });
      return (i) => tests.some((t) => t(i));
    }
    case 'has': {
      const tests: Pred[] = alts.map((a) => {
        switch (a) {
          case 'assignee':
            return (i: Issue) => i.assignee !== null;
          case 'due':
            return (i: Issue) => i.due !== null;
          case 'points':
            return (i: Issue) => i.points !== null;
          case 'labels':
            return (i: Issue) => i.labels.length > 0;
          case 'comments':
            return (i: Issue) => i.comments.length > 0;
          case 'reporter':
            return (i: Issue) => i.reporter !== null;
        }
        return bad(a);
      });
      return (i) => tests.some((t) => t(i));
    }
    case 'view': {
      const name = whole;
      if (!views.has(name)) fail(`query: unknown view '${name}'`);
      refs.push(name);
      let cache: Pred | null | undefined;
      return (i) => {
        if (cache === undefined) {
          cache = parseQuery(views.get(name) ?? '').filter;
        }
        return cache === null || cache(i);
      };
    }
  }
  return bad(whole);
}

// ---------------------------------------------------------------- list / sort

interface Clauses {
  limitStr: string | null;
  sortStr: string | null;
  filterText: string;
}

// Textual extraction of the trailing `limit N` and the `sort` clause.
function splitClauses(text: string): Clauses {
  let t = text.trim();
  let limitStr: string | null = null;
  const lm = /(^|\s)limit\s+(\S+)$/.exec(t);
  if (lm) {
    limitStr = lm[2];
    t = t.slice(0, lm.index).trim();
  }
  let sortStr: string | null = null;
  const sm = /(^|\s)sort\s/.exec(t);
  if (sm) {
    sortStr = t.slice(sm.index + sm[0].length).trim();
    t = t.slice(0, sm.index).trim();
  }
  return { limitStr, sortStr, filterText: t };
}

function parseLimit(s: string | null): number | null {
  if (s === null) return null;
  const n = parseIntStrict(s);
  if (n === null) fail(`bad limit '${s}'`);
  return n;
}

function parseSortClause(s: string): SortKey[] {
  const keys: SortKey[] = [];
  for (const part of s.split(/[\s,]+/)) {
    if (part === '') continue;
    const desc = part.startsWith('-');
    const name = desc ? part.slice(1) : part;
    if (!SORT_FIELDS.includes(name)) fail(`bad sort field '${name}'`);
    keys.push({ name, desc });
  }
  return keys;
}

interface Query {
  filter: Pred | null;
  sort: SortKey[] | null;
  limit: number | null;
}

function parseQuery(text: string, refs: string[] = []): Query {
  const c = splitClauses(text);
  const limit = parseLimit(c.limitStr);
  const filter = parseFilter(c.filterText, refs);
  const sort = c.sortStr === null ? null : parseSortClause(c.sortStr);
  return { filter, sort, limit };
}

function cmpField(a: Issue, b: Issue, f: string): number {
  switch (f) {
    case 'id':
      return a.id - b.id;
    case 'created':
      return a.created - b.created;
    case 'updated':
      return a.updated - b.updated;
    case 'priority':
      return RANK[a.priority] - RANK[b.priority];
    case 'state': {
      const w = wf as Workflow;
      return (w.stateIdx.get(a.state) ?? 0) - (w.stateIdx.get(b.state) ?? 0);
    }
    case 'points':
      return cmpOpt(a.points, b.points, (x, y) => x - y);
    case 'title':
      return ciCmp(a.title, b.title);
    case 'assignee':
      return cmpOpt(a.assignee, b.assignee, ciCmp);
    case 'reporter':
      return cmpOpt(a.reporter, b.reporter, ciCmp);
    case 'due':
      return cmpOpt(a.due, b.due, strCmp);
  }
  return 0;
}

function cmpIssues(a: Issue, b: Issue, keys: SortKey[]): number {
  for (const k of keys) {
    const c = cmpField(a, b, k.name);
    if (c !== 0) return k.desc ? -c : c;
  }
  return a.id - b.id;
}

function issueLine(i: Issue): string {
  return `#${i.id} | ${i.state} | ${i.priority} | ${i.assignee ?? '-'} | ${i.points ?? '-'} | ${i.due ?? '-'} | ${
    i.labels.length ? i.labels.join(',') : '-'
  } | ${i.title}`;
}

function listIssues(filter: Pred | null, sort: SortKey[], limit: number | null): void {
  let res = [...issues.values()].filter((i) => filter === null || filter(i));
  res.sort((a, b) => cmpIssues(a, b, sort));
  if (limit !== null) res = res.slice(0, limit);
  for (const i of res) emit(issueLine(i));
  emit(`(${res.length} ${res.length === 1 ? 'issue' : 'issues'})`);
}

function cmdList(rest: string): void {
  const q = parseQuery(rest);
  listIssues(q.filter, q.sort ?? [], q.limit);
}

// ---------------------------------------------------------------- views

// Direct view references of a stored view text.
function directRefs(text: string): string[] {
  const refs: string[] = [];
  parseFilter(splitClauses(text).filterText, refs);
  return refs;
}

// All views reachable from the given names (transitively).
function reachable(start: string[]): Set<string> {
  const seen = new Set<string>();
  const stack = [...start];
  while (stack.length > 0) {
    const v = stack.pop() as string;
    if (seen.has(v)) continue;
    seen.add(v);
    const t = views.get(v);
    if (t !== undefined) stack.push(...directRefs(t));
  }
  return seen;
}

function cmdView(rest: string): void {
  const [sub, r1] = nextWord(rest);
  switch (sub) {
    case 'save': {
      const [name, q0] = nextWord(r1);
      if (name === '') fail('usage: view save NAME QUERY');
      if (!VIEW_RE.test(name)) fail(`bad view name '${name}'`);
      const q = q0.trim();
      const refs: string[] = [];
      parseQuery(q, refs);
      if (reachable(refs).has(name)) fail(`view '${name}' would reference itself`);
      views.set(name, q);
      emit(`saved view ${name}`);
      return;
    }
    case 'run': {
      const [name, r2] = nextWord(r1);
      if (name === '') fail('usage: view run NAME [sort FIELDS] [limit N]');
      const c = splitClauses(r2);
      const limit = parseLimit(c.limitStr);
      if (c.filterText !== '') fail(`unexpected '${c.filterText}'`);
      const v = views.get(name);
      if (v === undefined) fail(`unknown view '${name}'`);
      const q = parseQuery(v);
      const sort = c.sortStr !== null ? parseSortClause(c.sortStr) : (q.sort ?? []);
      listIssues(q.filter, sort, limit !== null ? limit : q.limit);
      return;
    }
    case 'list': {
      const names = [...views.keys()].sort(strCmp);
      if (names.length === 0) emit('(no views)');
      for (const n of names) emit(`${n}: ${views.get(n)}`);
      return;
    }
    case 'show': {
      const w = words(r1);
      if (w.length !== 1) fail('usage: view show NAME');
      const v = views.get(w[0]);
      if (v === undefined) fail(`unknown view '${w[0]}'`);
      emit(`${w[0]}: ${v}`);
      return;
    }
    case 'delete': {
      const w = words(r1);
      if (w.length !== 1) fail('usage: view delete NAME');
      const name = w[0];
      if (!views.has(name)) fail(`unknown view '${name}'`);
      for (const other of [...views.keys()].sort(strCmp)) {
        if (other === name) continue;
        const t = views.get(other) as string;
        if (reachable(directRefs(t)).has(name)) fail(`view '${name}' is used by '${other}'`);
      }
      views.delete(name);
      emit(`deleted view ${name}`);
      return;
    }
    default:
      fail('usage: view save|run|list|show|delete');
  }
}

// ---------------------------------------------------------------- bulk

function cmdBulk(rest: string): void {
  const m = /(^|\s)where(\s|$)/.exec(rest);
  if (!m) fail('usage: bulk ACTION... where QUERY');
  const actionText = rest.slice(0, m.index).trim();
  const queryText = rest.slice(m.index + m[0].length);
  if (actionText === '') fail('usage: bulk ACTION... where QUERY');
  const toks = tokenize(actionText);
  const act = toks[0];
  const args = toks.slice(1);
  let apply: (id: number) => void;
  switch (act) {
    case 'move':
      if (args.length !== 1) fail('usage: bulk move STATE where QUERY');
      apply = (id) => doMove(String(id), args[0], null);
      break;
    case 'assign':
      if (args.length !== 1) fail('usage: bulk assign NAME where QUERY');
      apply = (id) => doEdit(String(id), ['assignee=' + args[0]]);
      break;
    case 'label':
      if (args.length < 1) fail('usage: bulk label +label... where QUERY');
      apply = (id) => doLabel(String(id), args);
      break;
    case 'set':
      if (args.length < 1) fail('usage: bulk set field=value... where QUERY');
      apply = (id) => doEdit(String(id), args);
      break;
    default:
      fail(`unknown bulk action '${act}'`);
  }
  const pred = parseFilter(queryText);
  const matched = [...issues.values()]
    .filter((i) => pred === null || pred(i))
    .map((i) => i.id)
    .sort((a, b) => a - b);
  let ok = 0;
  let failed = 0;
  for (const id of matched) {
    try {
      apply(id);
      ok++;
    } catch (e) {
      if (!(e instanceof CmdError)) throw e;
      emit(`#${id} error: ${e.message}`);
      failed++;
    }
  }
  emit(`bulk: ${ok} ok, ${failed} failed`);
}

// ---------------------------------------------------------------- reports

function cmdReport(rest: string): void {
  const [sub, r1] = nextWord(rest);
  switch (sub) {
    case 'summary': {
      const all = [...issues.values()];
      const open = all.filter((i) => !isFinal(i));
      emit(`issues: ${all.length} (open ${open.length}, final ${all.length - open.length})`);
      emit('by state:');
      if (wf !== null) {
        for (const s of wf.states) emit(`  ${s}: ${all.filter((i) => i.state === s).length}`);
      }
      emit('by priority:');
      for (const p of ['critical', 'high', 'medium', 'low']) {
        emit(`  ${p}: ${all.filter((i) => i.priority === p).length}`);
      }
      emit(`unassigned: ${open.filter((i) => i.assignee === null).length}`);
      emit(`overdue: ${open.filter(isOverdue).length}`);
      emit(`open points: ${open.reduce((s, i) => s + (i.points ?? 0), 0)}`);
      return;
    }
    case 'workload': {
      const open = [...issues.values()].filter((i) => !isFinal(i));
      if (open.length === 0) {
        emit('(no open issues)');
        return;
      }
      interface G {
        name: string;
        n: number;
        pts: number;
      }
      const groups = new Map<string, G>();
      const un: G = { name: 'unassigned', n: 0, pts: 0 };
      for (const i of open) {
        const pts = i.points ?? 0;
        if (i.assignee === null) {
          un.n++;
          un.pts += pts;
          continue;
        }
        const key = i.assignee.toLowerCase();
        let g = groups.get(key);
        if (!g) {
          g = { name: i.assignee, n: 0, pts: 0 };
          groups.set(key, g);
        }
        g.n++;
        g.pts += pts;
      }
      const arr = [...groups.values()].sort((a, b) => b.pts - a.pts || b.n - a.n || ciCmp(a.name, b.name));
      for (const g of arr) emit(`${g.name}: ${g.n} ${g.n === 1 ? 'issue' : 'issues'}, ${g.pts} points`);
      if (un.n > 0) emit(`unassigned: ${un.n} ${un.n === 1 ? 'issue' : 'issues'}, ${un.pts} points`);
      return;
    }
    case 'labels': {
      const pred = parseFilter(r1);
      const counts = new Map<string, number>();
      for (const i of issues.values()) {
        if (pred !== null && !pred(i)) continue;
        for (const l of i.labels) counts.set(l, (counts.get(l) ?? 0) + 1);
      }
      if (counts.size === 0) {
        emit('(no labels)');
        return;
      }
      const arr = [...counts.entries()].sort((a, b) => b[1] - a[1] || strCmp(a[0], b[0]));
      for (const [l, n] of arr) emit(`${l}: ${n}`);
      return;
    }
    case 'timeline': {
      const w = words(r1);
      if (w.length !== 1) fail('usage: report timeline ID');
      const id = parseId(w[0]);
      const iss = liveIssue(id);
      const wfNow = wf as Workflow;
      const periods: { state: string; from: number; to: number }[] = [];
      let cur = wfNow.initial;
      let from = iss.created;
      for (const e of log) {
        if (e.id !== id) continue;
        const m = /^state: (\S+) -> (\S+)$/.exec(e.detail);
        if (!m) continue;
        periods.push({ state: cur, from, to: e.t });
        cur = m[2];
        from = e.t;
      }
      periods.push({ state: cur, from, to: clock });
      for (const p of periods) emit(`${p.state}: t=${p.from}..${p.to} (${p.to - p.from})`);
      return;
    }
    default:
      fail('usage: report summary|workload|labels|timeline');
  }
}

// ---------------------------------------------------------------- dispatch & main

function cmdActor(rest: string): void {
  const w = words(rest);
  if (w.length !== 1) fail('usage: actor NAME');
  actor = w[0];
  emit(`actor is ${actor}`);
}

function cmdToday(rest: string): void {
  const w = words(rest);
  if (w.length !== 1) fail('usage: today DATE');
  if (!validDate(w[0])) fail(`bad date '${w[0]}'`);
  today = w[0];
  emit(`today is ${today}`);
}

function dispatch(cmd: string, rest: string): void {
  switch (cmd) {
    case 'actor':
      return cmdActor(rest);
    case 'today':
      return cmdToday(rest);
    case 'create':
      return cmdCreate(rest);
    case 'edit':
      return cmdEdit(rest);
    case 'label':
      return cmdLabel(rest);
    case 'assign':
      return cmdAssign(rest);
    case 'move':
      return cmdMove(rest);
    case 'comment':
      return cmdComment(rest);
    case 'delete':
      return cmdDelete(rest);
    case 'show':
      return cmdShow(rest);
    case 'list':
      return cmdList(rest);
    case 'view':
      return cmdView(rest);
    case 'bulk':
      return cmdBulk(rest);
    case 'log':
      return cmdLog(rest);
    case 'report':
      return cmdReport(rest);
    default:
      fail(`unknown command '${cmd}'`);
  }
}

function main(): void {
  const text = readFileSync(0, 'utf8');
  const lines = text.split('\n').map((l) => (l.endsWith('\r') ? l.slice(0, -1) : l));
  let i = 0;
  while (i < lines.length) {
    const raw = lines[i++];
    const trimmed = raw.trim();
    if (trimmed === '' || trimmed.startsWith('#')) continue;
    const line = raw.replace(/\s+$/, '');
    emit('> ' + line);
    const [cmd, rest] = nextWord(line.replace(/^\s+/, ''));
    try {
      if (cmd === 'workflow') {
        const body: string[] = [];
        while (i < lines.length && lines[i].trim() !== 'end') body.push(lines[i++]);
        if (i < lines.length) i++;
        defineWorkflow(body);
      } else {
        dispatch(cmd, rest);
      }
    } catch (e) {
      if (e instanceof CmdError) emit(`error: ${e.message}`);
      else emit(`error: ${e instanceof Error ? e.message : String(e)}`);
    }
  }
  process.stdout.write(out.join('\n') + (out.length > 0 ? '\n' : ''));
}

main();
