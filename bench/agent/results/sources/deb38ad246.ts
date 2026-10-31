// Read stdin, write stdout. See TASK.md.
import { readFileSync } from 'node:fs';

const BAD = 'error: bad command';
const NUM = /^[0-9]{1,6}$/;
const ITEM = /^([0-9]{1,6}):([0-9]{1,6})$/;

// Parse a number token; returns null if malformed.
function num(tok: string): number | null {
  return NUM.test(tok) ? parseInt(tok, 10) : null;
}

function lcs(a: string, b: string): number {
  const n = b.length;
  let prev = new Int32Array(n + 1);
  let cur = new Int32Array(n + 1);
  for (let i = 1; i <= a.length; i++) {
    cur[0] = 0;
    const ca = a.charCodeAt(i - 1);
    for (let j = 1; j <= n; j++) {
      if (ca === b.charCodeAt(j - 1)) cur[j] = prev[j - 1] + 1;
      else cur[j] = prev[j] > cur[j - 1] ? prev[j] : cur[j - 1];
    }
    [prev, cur] = [cur, prev];
  }
  return prev[n];
}

function edit(a: string, b: string): number {
  const n = b.length;
  let prev = new Int32Array(n + 1);
  let cur = new Int32Array(n + 1);
  for (let j = 0; j <= n; j++) prev[j] = j;
  for (let i = 1; i <= a.length; i++) {
    cur[0] = i;
    const ca = a.charCodeAt(i - 1);
    for (let j = 1; j <= n; j++) {
      const sub = prev[j - 1] + (ca === b.charCodeAt(j - 1) ? 0 : 1);
      const del = prev[j] + 1;
      const ins = cur[j - 1] + 1;
      cur[j] = Math.min(sub, del, ins);
    }
    [prev, cur] = [cur, prev];
  }
  return prev[n];
}

function knap(cap: number, items: [number, number][]): number {
  // Only weights up to total weight matter; clamp capacity to keep the table small.
  let total = 0;
  for (const [w] of items) total += w;
  const C = Math.min(cap, total);
  const best = new Float64Array(C + 1);
  for (const [w, v] of items) {
    if (w > C) continue;
    for (let c = C; c >= w; c--) {
      const cand = best[c - w] + v;
      if (cand > best[c]) best[c] = cand;
    }
  }
  return best[C];
}

function coins(amount: number, dens: number[]): string {
  const INF = 0x3fffffff;
  const dp = new Int32Array(amount + 1).fill(INF);
  dp[0] = 0;
  for (const c of dens) {
    if (c > amount) continue;
    for (let x = c; x <= amount; x++) {
      const cand = dp[x - c] + 1;
      if (cand < dp[x]) dp[x] = cand;
    }
  }
  return dp[amount] >= INF ? 'impossible' : String(dp[amount]);
}

function handle(line: string): string {
  const t = line.split(' ');
  const cmd = t[0];
  if (cmd === 'lcs' || cmd === 'edit') {
    if (t.length !== 3) return BAD;
    const a = t[1];
    const b = t[2];
    return String(cmd === 'lcs' ? lcs(a, b) : edit(a, b));
  }
  if (cmd === 'knap') {
    if (t.length < 2) return BAD;
    const cap = num(t[1]);
    if (cap === null) return BAD;
    const items: [number, number][] = [];
    for (let i = 2; i < t.length; i++) {
      const m = ITEM.exec(t[i]);
      if (!m) return BAD;
      const w = parseInt(m[1], 10);
      const v = parseInt(m[2], 10);
      if (w === 0) return BAD;
      items.push([w, v]);
    }
    return String(knap(cap, items));
  }
  if (cmd === 'coins') {
    if (t.length < 3) return BAD;
    const amount = num(t[1]);
    if (amount === null) return BAD;
    const dens: number[] = [];
    for (let i = 2; i < t.length; i++) {
      const c = num(t[i]);
      if (c === null || c === 0) return BAD;
      dens.push(c);
    }
    return coins(amount, dens);
  }
  return BAD;
}

// Read as latin1 so each byte maps to one char: comparisons are byte-wise.
const input = readFileSync(0).toString('latin1');
const out: string[] = [];
for (let line of input.split('\n')) {
  if (line.endsWith('\r')) line = line.slice(0, -1);
  if (/^ *$/.test(line)) continue;
  out.push(handle(line));
}
if (out.length > 0) process.stdout.write(out.join('\n') + '\n');
