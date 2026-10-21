// Read stdin, write stdout. See TASK.md.
import { readFileSync } from 'node:fs';

type Op = { kind: ' ' | '-' | '+'; a: number; b: number; text: string };

const input = readFileSync(0, 'utf8');
const lines = input.split('\n');
const header = lines[0].split(' ');
const nameA = header[0];
const nameB = header[1];
const context = Number(header[2]);
const n = Number(header[3]);
const m = Number(header[4]);

const strip = (s: string) => (s.endsWith('\r') ? s.slice(0, -1) : s);
const a = lines.slice(1, 1 + n).map(strip);
const b = lines.slice(1 + n, 1 + n + m).map(strip);

// L[i][j] = LCS length of a[i..] and b[j..], stored flat with row width m + 1.
const w = m + 1;
const L = new Int32Array((n + 1) * w);
for (let i = n - 1; i >= 0; i--) {
  for (let j = m - 1; j >= 0; j--) {
    L[i * w + j] =
      a[i] === b[j]
        ? L[(i + 1) * w + j + 1] + 1
        : Math.max(L[(i + 1) * w + j], L[i * w + j + 1]);
  }
}

// Walk the edit script exactly as specified.
const ops: Op[] = [];
{
  let i = 0;
  let j = 0;
  while (!(i === n && j === m)) {
    if (i < n && j < m && a[i] === b[j]) {
      ops.push({ kind: ' ', a: i, b: j, text: a[i] });
      i++;
      j++;
    } else if (j === m || (i < n && L[(i + 1) * w + j] >= L[i * w + j + 1])) {
      ops.push({ kind: '-', a: i, b: j, text: a[i] });
      i++;
    } else {
      ops.push({ kind: '+', a: i, b: j, text: b[j] });
      j++;
    }
  }
}

const changes: number[] = [];
ops.forEach((op, k) => {
  if (op.kind !== ' ') changes.push(k);
});

const out: string[] = [];
if (changes.length > 0) {
  out.push(`--- ${nameA}`, `+++ ${nameB}`);

  // Group changes into hunks: a gap of at most 2 * context unchanged lines joins them.
  let g = 0;
  while (g < changes.length) {
    let last = g;
    while (last + 1 < changes.length && changes[last + 1] - changes[last] - 1 <= 2 * context) {
      last++;
    }
    const first = changes[g];
    const lastChange = changes[last];
    const start = Math.max(0, first - context);
    const end = Math.min(ops.length - 1, lastChange + context);

    // Position in A and B before the hunk's first line.
    const startA = start < ops.length ? ops[start].a : n;
    const startB = start < ops.length ? ops[start].b : m;

    let countA = 0;
    let countB = 0;
    for (let k = start; k <= end; k++) {
      if (ops[k].kind !== '+') countA++;
      if (ops[k].kind !== '-') countB++;
    }

    const range = (s: number, count: number) =>
      count === 1 ? `${s}` : `${s},${count}`;
    const sA = countA > 0 ? startA + 1 : startA;
    const sB = countB > 0 ? startB + 1 : startB;
    out.push(`@@ -${range(sA, countA)} +${range(sB, countB)} @@`);
    for (let k = start; k <= end; k++) {
      out.push(ops[k].kind + ops[k].text);
    }

    g = last + 1;
  }
}

if (out.length > 0) {
  process.stdout.write(out.join('\n') + '\n');
}
