// mini-vcs: an in-memory git-like VCS driven by a script on stdin. See TASK.md.
import { readFileSync } from 'node:fs';

type Tree = Map<string, string>;
type MergeKind = 'content' | 'add/add' | 'modify/delete';
interface Commit {
  id: string;
  parents: string[];
  message: string;
  tree: Tree;
  num: number;
}
type Head = { kind: 'branch'; name: string } | { kind: 'detached'; id: string };
interface MergeState {
  other: string;
  branch: string;
  conflicts: Map<string, MergeKind>;
}

class CmdError extends Error {}
function fail(msg: string): never {
  throw new CmdError(msg);
}

const out: string[] = [];
const say = (s: string): void => {
  out.push(s);
};

// ---------- hashing ----------

const FNV_OFFSET = 14695981039346656037n;
const FNV_PRIME = 1099511628211n;
const MASK64 = (1n << 64n) - 1n;

function hash(text: string): string {
  let h = FNV_OFFSET;
  for (const b of Buffer.from(text, 'utf8')) {
    h ^= BigInt(b);
    h = (h * FNV_PRIME) & MASK64;
  }
  return h.toString(16).padStart(16, '0');
}

const short = (id: string): string => id.slice(0, 7);
const byteCmp = (a: string, b: string): number =>
  Buffer.compare(Buffer.from(a, 'utf8'), Buffer.from(b, 'utf8'));
const sortNames = (names: Iterable<string>): string[] => [...names].sort(byteCmp);

function treeHash(t: Tree): string {
  const text = sortNames(t.keys())
    .map((n) => `${n} ${hash(t.get(n)!)}\n`)
    .join('');
  return hash(text);
}

function sameTree(a: Tree, b: Tree): boolean {
  if (a.size !== b.size) return false;
  for (const [k, v] of a) if (b.get(k) !== v) return false;
  return true;
}

// ---------- content helpers ----------

// Content is lines each followed by "\n"; returns the lines.
function linesOf(c: string | undefined): string[] {
  if (!c) return [];
  const parts = c.split('\n');
  parts.pop();
  return parts;
}
const textOf = (ls: string[]): string => ls.map((l) => l + '\n').join('');
const arrEq = (a: string[], b: string[]): boolean =>
  a.length === b.length && a.every((x, i) => x === b[i]);

// ---------- repository state ----------

const files: Tree = new Map(); // working tree
let index: Tree = new Map(); // staging area
const commits = new Map<string, Commit>();
const branches = new Map<string, string | null>([['main', null]]); // null = unborn
const tags = new Map<string, string>();
let head: Head = { kind: 'branch', name: 'main' };
let merge: MergeState | null = null;
let nextNum = 1;

const headCommit = (): string | null =>
  head.kind === 'detached' ? head.id : (branches.get(head.name) ?? null);
const commitOf = (id: string): Commit => commits.get(id)!;
const headTree = (): Tree => {
  const c = headCommit();
  return c === null ? new Map() : commitOf(c).tree;
};
const label = (): string => (head.kind === 'branch' ? head.name : 'detached');
const isConflicted = (n: string): boolean => merge !== null && merge.conflicts.has(n);
const clearConflict = (n: string): void => {
  merge?.conflicts.delete(n);
};

function moveHead(id: string): void {
  if (head.kind === 'branch') branches.set(head.name, id);
  else head = { kind: 'detached', id };
}

function makeCommit(parents: string[], tree: Tree, message: string): string {
  const text =
    `tree ${treeHash(tree)}\n` +
    parents.map((p) => `parent ${p}\n`).join('') +
    `\n` +
    message +
    `\n`;
  const id = hash(text);
  if (!commits.has(id)) {
    commits.set(id, { id, parents, message, tree: new Map(tree), num: nextNum++ });
  }
  return id;
}

function ancestors(id: string | null): Set<string> {
  const seen = new Set<string>();
  if (id === null) return seen;
  const stack = [id];
  while (stack.length > 0) {
    const c = stack.pop()!;
    if (seen.has(c)) continue;
    seen.add(c);
    for (const p of commitOf(c).parents) stack.push(p);
  }
  return seen;
}

// ---------- refs ----------

function resolveRef(ref: string): string {
  const tilde = ref.indexOf('~');
  const base = tilde < 0 ? ref : ref.slice(0, tilde);
  let steps = 0;
  if (tilde >= 0) {
    const ns = ref.slice(tilde + 1);
    if (!/^\d+$/.test(ns)) fail(`unknown revision '${ref}'`);
    steps = Number(ns);
  }
  let id: string | undefined;
  if (base === 'HEAD') {
    id = headCommit() ?? undefined;
  } else if (branches.get(base)) {
    id = branches.get(base) as string;
  } else if (tags.has(base)) {
    id = tags.get(base);
  } else if (/^[0-9a-f]{4,}$/.test(base)) {
    const matches = [...commits.keys()].filter((c) => c.startsWith(base));
    if (matches.length > 1) fail(`ambiguous revision '${ref}'`);
    id = matches[0];
  }
  if (id === undefined) fail(`unknown revision '${ref}'`);
  for (let k = 0; k < steps; k++) {
    const ps = commitOf(id).parents;
    if (ps.length === 0) fail(`unknown revision '${ref}'`);
    id = ps[0];
  }
  return id;
}

// ---------- line diff ----------

// Matching pairs as the spec's LCS walk.
function matchPairs(A: string[], B: string[]): [number, number][] {
  const n = A.length;
  const m = B.length;
  const W = m + 1;
  const L = new Int32Array((n + 1) * W);
  for (let i = n - 1; i >= 0; i--) {
    for (let j = m - 1; j >= 0; j--) {
      L[i * W + j] =
        A[i] === B[j]
          ? 1 + L[(i + 1) * W + j + 1]
          : Math.max(L[(i + 1) * W + j], L[i * W + j + 1]);
    }
  }
  const pairs: [number, number][] = [];
  let i = 0;
  let j = 0;
  while (i < n && j < m) {
    if (A[i] === B[j]) {
      pairs.push([i, j]);
      i++;
      j++;
    } else if (L[(i + 1) * W + j] >= L[i * W + j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return pairs;
}

function lineDiff(A: string[], B: string[]): string[] {
  const res: string[] = [];
  let pi = 0;
  let pj = 0;
  for (const [i, j] of matchPairs(A, B)) {
    while (pi < i) res.push(`- ${A[pi++]}`);
    while (pj < j) res.push(`+ ${B[pj++]}`);
    res.push(`  ${A[i]}`);
    pi = i + 1;
    pj = j + 1;
  }
  while (pi < A.length) res.push(`- ${A[pi++]}`);
  while (pj < B.length) res.push(`+ ${B[pj++]}`);
  return res;
}

// ---------- three-way line merge ----------

function mergeLines(
  base: string[],
  ours: string[],
  theirs: string[],
  branch: string,
): { text: string; conflict: boolean } {
  const bo = new Map(matchPairs(base, ours));
  const bt = new Map(matchPairs(base, theirs));
  const stable: [number, number, number][] = [];
  for (const [bi, oi] of bo) {
    const ti = bt.get(bi);
    if (ti !== undefined) stable.push([bi, oi, ti]);
  }
  stable.sort((x, y) => x[0] - y[0]);

  const res: string[] = [];
  let conflict = false;
  let pb = -1;
  let po = -1;
  let pt = -1;
  for (let k = 0; k <= stable.length; k++) {
    const [sb, so, st] =
      k < stable.length ? stable[k] : [base.length, ours.length, theirs.length];
    const bc = base.slice(pb + 1, sb);
    const oc = ours.slice(po + 1, so);
    const tc = theirs.slice(pt + 1, st);
    if (arrEq(oc, bc)) {
      res.push(...tc);
    } else if (arrEq(tc, bc)) {
      res.push(...oc);
    } else if (arrEq(oc, tc)) {
      res.push(...oc);
    } else {
      conflict = true;
      res.push('<<<<<<< HEAD', ...oc, '=======', ...tc, `>>>>>>> ${branch}`);
    }
    if (k < stable.length) res.push(base[sb]);
    pb = sb;
    po = so;
    pt = st;
  }
  return { text: textOf(res), conflict };
}

// ---------- shared checks / working tree updates ----------

function isDirty(): boolean {
  if (!sameTree(index, headTree())) return true;
  for (const [n, c] of index) if (files.get(n) !== c) return true;
  return false;
}

function checkSwitch(target: Tree): void {
  if (isDirty()) fail('local changes would be overwritten');
  checkUntracked(target);
}

function checkUntracked(target: Tree): void {
  for (const n of sortNames(target.keys())) {
    if (!index.has(n) && files.has(n)) fail(`untracked file would be overwritten: ${n}`);
  }
}

// Set index to target tree and update working files (delete old index files first).
function switchTree(target: Tree): void {
  for (const n of index.keys()) files.delete(n);
  for (const [n, c] of target) files.set(n, c);
  index = new Map(target);
}

function resetTo(target: string): void {
  const oldIndex = index;
  const oldHead = headTree();
  moveHead(target);
  const tree = commitOf(target).tree;
  for (const n of oldIndex.keys()) files.delete(n);
  for (const n of oldHead.keys()) files.delete(n);
  for (const [n, c] of tree) files.set(n, c);
  index = new Map(tree);
  merge = null;
}

// ---------- commands ----------

function cmdAdd(args: string[]): void {
  if (args.length === 0) fail('usage: add PATH...');
  for (const p of args) {
    if (p === '.') {
      for (const n of sortNames(files.keys())) {
        index.set(n, files.get(n)!);
        clearConflict(n);
      }
      for (const n of [...index.keys()]) {
        if (!files.has(n)) {
          index.delete(n);
          clearConflict(n);
        }
      }
    } else if (files.has(p)) {
      index.set(p, files.get(p)!);
      clearConflict(p);
    } else if (index.has(p)) {
      index.delete(p);
      clearConflict(p);
    } else if (isConflicted(p)) {
      clearConflict(p);
    } else {
      fail(`pathspec '${p}' did not match any files`);
    }
  }
}

function cmdStatus(): void {
  const ht = headTree();
  const staged: string[] = [];
  for (const n of sortNames(new Set([...ht.keys(), ...index.keys()]))) {
    if (isConflicted(n)) continue;
    const h = ht.get(n);
    const i = index.get(n);
    if (h === undefined && i !== undefined) staged.push(`new file: ${n}`);
    else if (h !== undefined && i === undefined) staged.push(`deleted: ${n}`);
    else if (h !== i) staged.push(`modified: ${n}`);
  }
  const unstaged: string[] = [];
  for (const n of sortNames(index.keys())) {
    if (isConflicted(n)) continue;
    const w = files.get(n);
    if (w === undefined) unstaged.push(`deleted: ${n}`);
    else if (w !== index.get(n)) unstaged.push(`modified: ${n}`);
  }
  const conflicts = merge ? sortNames(merge.conflicts.keys()).map((n) => `unmerged: ${n}`) : [];
  const untracked = sortNames(files.keys()).filter((n) => !index.has(n) && !isConflicted(n));

  say(head.kind === 'branch' ? `On branch ${head.name}` : `HEAD detached at ${short(head.id)}`);
  if (merge) say(`merging: ${merge.branch}`);
  const sections: [string, string[]][] = [
    ['staged:', staged],
    ['unstaged:', unstaged],
    ['conflicts:', conflicts],
    ['untracked:', untracked],
  ];
  const nonEmpty = sections.filter(([, items]) => items.length > 0);
  if (nonEmpty.length === 0) {
    say('nothing to commit, working tree clean');
    return;
  }
  for (const [heading, items] of nonEmpty) {
    say(heading);
    for (const it of items) say(`  ${it}`);
  }
}

function cmdCommit(msg: string): void {
  if (msg === '') fail('empty commit message');
  if (merge && merge.conflicts.size > 0) {
    fail(`unresolved conflicts: ${sortNames(merge.conflicts.keys()).join(' ')}`);
  }
  const cur = headCommit();
  if (merge) {
    const id = makeCommit([cur!, merge.other], index, msg);
    moveHead(id);
    merge = null;
    say(`[${label()} ${short(id)}] ${msg}`);
    return;
  }
  if (sameTree(index, headTree())) fail('nothing to commit');
  const id = makeCommit(cur === null ? [] : [cur], index, msg);
  const rootTag = cur === null ? ' (root-commit)' : '';
  moveHead(id);
  say(`[${label()}${rootTag} ${short(id)}] ${msg}`);
}

function cmdLog(args: string[]): void {
  let limit = Infinity;
  if (args.length === 2 && args[0] === '-n' && /^\d+$/.test(args[1])) {
    limit = Number(args[1]);
  } else if (args.length !== 0) {
    fail('usage: log [-n N]');
  }
  const cur = headCommit();
  if (cur === null) fail('no commits yet');
  const list = [...ancestors(cur)].map((id) => commitOf(id)).sort((a, b) => b.num - a.num);
  for (const c of list.slice(0, limit)) {
    let line = `${short(c.id)} ${c.message}`;
    if (c.parents.length === 2) {
      line += ` (merge ${short(c.parents[0])} ${short(c.parents[1])})`;
    }
    say(line);
  }
}

function cmdDiff(args: string[]): void {
  if (args.length > 2) fail('usage: diff [REF [REF]]');
  const treeOfRef = (r: string): Tree => commitOf(resolveRef(r)).tree;
  let left: Tree;
  let right: Tree;
  if (args.length === 0) {
    left = index;
    right = files;
  } else if (args.length === 1) {
    left = treeOfRef(args[0]);
    right = files;
  } else {
    left = treeOfRef(args[0]);
    right = treeOfRef(args[1]);
  }
  let any = false;
  for (const n of sortNames(new Set([...left.keys(), ...right.keys()]))) {
    const l = left.get(n);
    const r = right.get(n);
    if (l === r) continue;
    any = true;
    say(`diff ${n}`);
    if (l === undefined) say('new file');
    if (r === undefined) say('deleted file');
    for (const line of lineDiff(linesOf(l), linesOf(r))) say(line);
  }
  if (!any) say('(no differences)');
}

function checkBranchLike(kind: 'branch' | 'tag', name: string): void {
  if (!/^[A-Za-z0-9._\/][A-Za-z0-9._\/-]*$/.test(name)) fail(`invalid ${kind} name '${name}'`);
}

function cmdBranch(args: string[]): void {
  if (args.length === 0) {
    const cur = head.kind === 'branch' ? head.name : null;
    if (head.kind === 'detached') say(`* (HEAD detached at ${short(head.id)})`);
    for (const n of sortNames(branches.keys())) {
      say(`${n === cur ? '* ' : '  '}${n}`);
    }
    return;
  }
  if (args.length === 1) {
    const name = args[0];
    checkBranchLike('branch', name);
    if (branches.has(name)) fail(`branch '${name}' already exists`);
    const cur = headCommit();
    if (cur === null) fail('no commits yet');
    branches.set(name, cur);
    return;
  }
  if (args.length === 2 && args[0] === '-d') {
    const name = args[1];
    const commit = branches.get(name);
    if (commit === undefined) fail(`branch '${name}' not found`);
    if (head.kind === 'branch' && head.name === name) {
      fail(`cannot delete the current branch '${name}'`);
    }
    if (commit === null || !ancestors(headCommit()).has(commit)) {
      fail(`branch '${name}' is not fully merged`);
    }
    branches.delete(name);
    say(`Deleted branch ${name} (was ${short(commit)}).`);
    return;
  }
  fail('usage: branch [NAME | -d NAME]');
}

function cmdTag(args: string[]): void {
  if (args.length === 0) {
    for (const n of sortNames(tags.keys())) say(n);
    return;
  }
  if (args.length > 2) fail('usage: tag [NAME [REF]]');
  const name = args[0];
  checkBranchLike('tag', name);
  if (tags.has(name)) fail(`tag '${name}' already exists`);
  const ref = args.length === 2 ? args[1] : 'HEAD';
  if (ref === 'HEAD' && headCommit() === null) fail('no commits yet');
  tags.set(name, resolveRef(ref));
}

function cmdShow(args: string[]): void {
  if (args.length !== 1) fail('usage: show REF');
  const id = resolveRef(args[0]);
  const c = commitOf(id);
  say(`commit ${id}`);
  say(`tree ${treeHash(c.tree)}`);
  for (const p of c.parents) say(`parent ${p}`);
  say(`message: ${c.message}`);
  say('files:');
  for (const n of sortNames(c.tree.keys())) {
    say(`  ${n} ${hash(c.tree.get(n)!).slice(0, 7)}`);
  }
}

function cmdCheckout(args: string[]): void {
  if (args.length === 2 && args[0] === '-b') {
    const name = args[1];
    checkBranchLike('branch', name);
    if (branches.has(name)) fail(`branch '${name}' already exists`);
    const cur = headCommit();
    if (cur === null) fail('no commits yet');
    checkSwitch(headTree());
    branches.set(name, cur);
    head = { kind: 'branch', name };
    say(`Switched to a new branch '${name}'`);
    return;
  }
  if (args.length !== 1) fail('usage: checkout REF | checkout -b NAME');
  if (merge) fail('merge in progress');
  const target = args[0];
  if (head.kind === 'branch' && head.name === target) {
    say(`Already on '${target}'`);
    return;
  }
  const bc = branches.get(target);
  if (bc) {
    checkSwitch(commitOf(bc).tree);
    switchTree(commitOf(bc).tree);
    head = { kind: 'branch', name: target };
    say(`Switched to branch '${target}'`);
    return;
  }
  const id = resolveRef(target);
  const c = commitOf(id);
  checkSwitch(c.tree);
  switchTree(c.tree);
  head = { kind: 'detached', id };
  say(`HEAD is now at ${short(id)} ${c.message}`);
}

function cmdReset(args: string[]): void {
  if (args.length === 0 || args[0] !== '--hard' || args.length > 2) {
    fail('usage: reset --hard [REF]');
  }
  let target: string;
  if (args.length === 2) {
    target = resolveRef(args[1]);
  } else {
    const h = headCommit();
    if (h === null) fail('no commits yet');
    target = h;
  }
  resetTo(target);
  say(`HEAD is now at ${short(target)} ${commitOf(target).message}`);
}

function cmdMerge(args: string[]): void {
  if (args.length === 1 && args[0] === '--abort') {
    if (!merge) fail('no merge in progress');
    resetTo(headCommit()!);
    say('Merge aborted.');
    return;
  }
  if (args.length !== 1) fail('usage: merge BRANCH');
  if (merge) fail('merge in progress');
  const cur = headCommit();
  if (cur === null) fail('no commits yet');
  const name = args[0];
  const other = branches.get(name);
  if (!other) fail(`unknown branch '${name}'`);
  if (isDirty()) fail('local changes would be overwritten');

  if (ancestors(cur).has(other)) {
    say('Already up to date.');
    return;
  }
  if (ancestors(other).has(cur)) {
    const tree = commitOf(other).tree;
    checkUntracked(tree);
    switchTree(tree);
    moveHead(other);
    say('Fast-forward');
    return;
  }

  // Three-way merge. Merge base: common ancestor with greatest creation number.
  const curAnc = ancestors(cur);
  const otherAnc = ancestors(other);
  let base: string | null = null;
  for (const id of curAnc) {
    if (otherAnc.has(id) && (base === null || commitOf(id).num > commitOf(base).num)) base = id;
  }
  const B: Tree = base === null ? new Map() : commitOf(base).tree;
  const O: Tree = headTree();
  const T: Tree = commitOf(other).tree;

  const newIndex: Tree = new Map();
  const workingEntries: Tree = new Map();
  const conflicts = new Map<string, MergeKind>();

  for (const n of sortNames(new Set([...B.keys(), ...O.keys(), ...T.keys()]))) {
    const b = B.get(n);
    const o = O.get(n);
    const t = T.get(n);
    let r: string | undefined;
    if (o === t) {
      r = o;
    } else if (o === b) {
      r = t;
    } else if (t === b) {
      r = o;
    } else if (o === undefined || t === undefined) {
      conflicts.set(n, 'modify/delete');
      if (o !== undefined) newIndex.set(n, o);
      workingEntries.set(n, (o ?? t)!);
      continue;
    } else {
      const m = mergeLines(linesOf(b), linesOf(o), linesOf(t), name);
      if (!m.conflict) {
        r = m.text;
      } else {
        conflicts.set(n, b === undefined ? 'add/add' : 'content');
        newIndex.set(n, o);
        workingEntries.set(n, m.text);
        continue;
      }
    }
    if (r !== undefined) {
      newIndex.set(n, r);
      workingEntries.set(n, r);
    }
  }

  // Untracked check for every name in the result or the working overrides.
  checkUntracked(workingEntries);

  // Apply to working tree and index.
  for (const n of index.keys()) if (!workingEntries.has(n)) files.delete(n);
  for (const [n, c] of workingEntries) files.set(n, c);
  index = newIndex;

  if (conflicts.size === 0) {
    const id = makeCommit([cur, other], index, `Merge branch '${name}'`);
    moveHead(id);
    say("Merge made by the 'three-way' strategy.");
    say(`[${label()} ${short(id)}] Merge branch '${name}'`);
  } else {
    merge = { other, branch: name, conflicts };
    for (const n of sortNames(conflicts.keys())) {
      const kind = conflicts.get(n)!;
      if (kind === 'modify/delete') say(`CONFLICT (modify/delete): ${n}`);
      else say(`CONFLICT (${kind}): Merge conflict in ${n}`);
    }
    say('Automatic merge failed; fix conflicts and then commit the result.');
  }
}

function cmdRmMvCat(cmd: string, args: string[]): void {
  if (cmd === 'rm') {
    if (args.length === 0) fail('usage: rm FILE...');
    for (const n of args) {
      if (!files.has(n)) fail(`no such file: ${n}`);
      files.delete(n);
    }
  } else if (cmd === 'mv') {
    if (args.length !== 2) fail('usage: mv OLD NEW');
    const [oldName, newName] = args;
    if (!files.has(oldName)) fail(`no such file: ${oldName}`);
    const content = files.get(oldName)!;
    files.delete(oldName);
    files.set(newName, content);
  } else {
    // cat
    if (args.length !== 1) fail('usage: cat FILE');
    if (!files.has(args[0])) fail(`no such file: ${args[0]}`);
    for (const l of linesOf(files.get(args[0]))) say(l);
  }
}

function cmdLs(): void {
  const names = sortNames(files.keys());
  if (names.length === 0) say('(empty)');
  for (const n of names) say(n);
}

// ---------- main loop ----------

const input = readFileSync(0, 'utf8');
const src = input.split('\n');
if (src.length > 0 && src[src.length - 1] === '') src.pop();
let pos = 0;

while (pos < src.length) {
  const raw = src[pos++];
  const trimmed = raw.trim();
  if (trimmed === '' || trimmed.startsWith('#')) continue;
  say(`> ${raw.trimEnd()}`);

  const parts = trimmed.split(/\s+/);
  const cmd = parts[0];
  const args = parts.slice(1);

  try {
    switch (cmd) {
      case 'write':
      case 'append': {
        if (args.length !== 1) fail(`usage: ${cmd} FILE`);
        const block: string[] = [];
        while (pos < src.length && src[pos] !== '.') block.push(src[pos++]);
        if (pos < src.length) pos++; // skip terminator
        if (cmd === 'write') files.set(args[0], textOf(block));
        else files.set(args[0], (files.get(args[0]) ?? '') + textOf(block));
        break;
      }
      case 'rm':
      case 'mv':
      case 'cat':
        cmdRmMvCat(cmd, args);
        break;
      case 'ls':
        cmdLs();
        break;
      case 'add':
        cmdAdd(args);
        break;
      case 'status':
        cmdStatus();
        break;
      case 'commit':
        cmdCommit(trimmed.slice(cmd.length).trim());
        break;
      case 'log':
        cmdLog(args);
        break;
      case 'diff':
        cmdDiff(args);
        break;
      case 'branch':
        cmdBranch(args);
        break;
      case 'tag':
        cmdTag(args);
        break;
      case 'show':
        cmdShow(args);
        break;
      case 'checkout':
        cmdCheckout(args);
        break;
      case 'reset':
        cmdReset(args);
        break;
      case 'merge':
        cmdMerge(args);
        break;
      default:
        fail(`unknown command '${cmd}'`);
    }
  } catch (e) {
    if (e instanceof CmdError) say(`error: ${e.message}`);
    else throw e;
  }
}

process.stdout.write(out.map((l) => l + '\n').join(''));
