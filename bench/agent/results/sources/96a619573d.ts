// Read stdin, write stdout. See TASK.md.
import readFileSync from 'node:fs';

const BAD = 'error: bad command';
const NUM = /^[0-9]{1,6}$/;

// Parses a 1-to-6-digit decimal number; anything else is malformed.
function num(tok: string | undefined): number | null {
  return tok !== undefined && NUM.test(tok) ? Number(tok) : null;
}

// Longest common subsequence over bytes, using two rolling rows.
function lcs(a: Buffer, b: Buffer): number {
  let prev = new Uint32Array(b.length + 1);
  let cur = new Uint32Array(b.length + 1);
  for (let i = 1; i <= a.length; i++) {
    for (let j = 1; j <= b.length; j++) {
      cur[j] = a[i - 1] === b[j - 1] ? prev[j - 1] + 1 : Math.max(prev[j], cur[j - 1]);
    }
    [prev, cur] = [cur, prev];
  }
  return prev[b.length];
}

// Levenshtein distance over bytes, using two rolling rows.
function edit(a: Buffer, b: Buffer): number {
  let prev = new Uint32Array(b.length + 1);
  let cur = new Uint32Array(b.length + 1);
  for (let j = 0; j <= b.length; j++) prev[j] = j;
  for (let i = 1; i <= a.length; i++) {
    cur[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const sub = prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1);
      cur[j] = Math.min(sub, prev[j] + 1, cur[j - 1] + 1);
    }
    [prev, cur] = [cur, prev];
  }
  return prev[b.length];
}

// 0/1 knapsack: best[c] is the best value achievable with capacity c.
// Iterating capacity downwards ensures each item is used at most once.
function knap(cap: number, items: [number, number][]): number {
  const best = new Float64Array(cap + 1);
  for (const [w, v] of items) {
    for (let c = cap; c >= w; c--) {
      best[c] = Math.max(best[c], best[c - w] + v);
    }
  }
  return best[cap];
}

// Unbounded coin change; null when the amount cannot be formed.
function coins(amount: number, denoms: number[]): number | null {
  const dp = new Float64Array(amount + 1).fill(Infinity);
  dp[0] = 0;
  for (let x = 1; x <= amount; x++) {
    for (const c of denoms) {
      if (c <= x && dp[x - c] + 1 < dp[x]) dp[x] = dp[x - c] + 1;
    }
  }
  return dp[amount] === Infinity ? null : dp[amount];
}

function run(line: string): string {
  const t = line.split(' ');
  switch (t[0]) {
    case 'lcs':
    case 'edit': {
      if (t.length !== 3 || !t[1] || !t[2]) return BAD;
      const a = Buffer.from(t[1], 'latin1');
      const b = Buffer.from(t[2], 'latin1');
      return String(t[0] === 'lcs' ? lcs(a, b) : edit(a, b));
    }
    case 'knap': {
      if (t.length < 2) return BAD;
      const cap = num(t[1]);
      if (cap === null) return BAD;
      const items: [number, number][] = [];
      for (const tok of t.slice(2)) {
        const parts = tok.split(':');
        if (parts.length !== 2) return BAD;
        const w = num(parts[0]);
        const v = num(parts[1]);
        if (w === null || v === null || w === 0) return BAD;
        items.push([w, v]);
      }
      return String(knap(cap, items));
    }
    case 'coins': {
      if (t.length < 3) return BAD;
      const amount = num(t[1]);
      if (amount === null) return BAD;
      const denoms: number[] = [];
      for (const tok of t.slice(2)) {
        const c = num(tok);
        if (c === null || c === 0) return BAD;
        denoms.push(c);
      }
      const result = coins(amount, denoms);
      return result === null ? 'impossible' : String(result);
    }
    default:
      return BAD;
  }
}

// Latin-1 keeps one character per byte, so token comparison is byte-based.
const input = readFileSync(0, 'latin1');
const out: string[] = [];
for (const raw of input.split('\n')) {
  const line = raw.endsWith('\r') ? raw.slice(0, -1) : raw;
  if (/^ *$/.test(line)) continue;
  out.push(run(line) + '\n');
}
process.stdout.write(out.join(''));
