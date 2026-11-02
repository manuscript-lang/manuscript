// Unified diff. Reads stdin, writes stdout. See TASK.md.
import { readFileSync } from 'node:fs';

interface Op {
  kind: ' ' | '-' | '+';
  text: string;
  ia: number; // number of A lines consumed before this op
  ib: number; // number of B lines consumed before this op
}

function main(): void {
  const raw = readFileSync(0, 'utf8');
  const lines = raw.split('\n').map((l) => (l.endsWith('\r') ? l.slice(0, -1) : l));

  const header = lines[0].trim().split(' ');
  const nameA = header[0];
  const nameB = header[1];
  const context = parseInt(header[2], 10);
  const n = parseInt(header[3], 10);
  const m = parseInt(header[4], 10);

  const a: string[] = [];
  for (let i = 0; i < n; i++) a.push(lines[1 + i] ?? '');
  const b: string[] = [];
  for (let j = 0; j < m; j++) b.push(lines[1 + n + j] ?? '');

  // L[i][j] = LCS length of a[i..] and b[j..], flattened with width m+1.
  const w = m + 1;
  const L = new Int32Array((n + 1) * w);
  for (let i = n - 1; i >= 0; i--) {
    for (let j = m - 1; j >= 0; j--) {
      if (a[i] === b[j]) {
        L[i * w + j] = L[(i + 1) * w + (j + 1)] + 1;
      } else {
        const down = L[(i + 1) * w + j];
        const right = L[i * w + (j + 1)];
        L[i * w + j] = down > right ? down : right;
      }
    }
  }

  // Build the edit script.
  const ops: Op[] = [];
  let i = 0;
  let j = 0;
  while (!(i === n && j === m)) {
    if (i < n && j < m && a[i] === b[j]) {
      ops.push({ kind: ' ', text: a[i], ia: i, ib: j });
      i++;
      j++;
    } else if (j === m || (i < n && L[(i + 1) * w + j] >= L[i * w + (j + 1)])) {
      ops.push({ kind: '-', text: a[i], ia: i, ib: j });
      i++;
    } else {
      ops.push({ kind: '+', text: b[j], ia: i, ib: j });
      j++;
    }
  }

  const changes: number[] = [];
  for (let k = 0; k < ops.length; k++) if (ops[k].kind !== ' ') changes.push(k);
  if (changes.length === 0) return;

  const out: string[] = [`--- ${nameA}`, `+++ ${nameB}`];

  // Group changes into hunks: merge when the unchanged gap is at most 2 * context.
  let g = 0;
  while (g < changes.length) {
    let h = g;
    while (h + 1 < changes.length && changes[h + 1] - changes[h] - 1 <= 2 * context) h++;

    const start = Math.max(changes[g] - context, 0);
    const end = Math.min(changes[h] + context, ops.length - 1);

    let la = 0;
    let lb = 0;
    const body: string[] = [];
    for (let k = start; k <= end; k++) {
      const op = ops[k];
      if (op.kind !== '+') la++;
      if (op.kind !== '-') lb++;
      body.push(`${op.kind}${op.text}`);
    }

    const startA = ops[start].ia;
    const startB = ops[start].ib;
    const sa = la > 0 ? startA + 1 : startA;
    const sb = lb > 0 ? startB + 1 : startB;

    const fmt = (s: number, l: number): string => (l === 1 ? `${s}` : `${s},${l}`);
    out.push(`@@ -${fmt(sa, la)} +${fmt(sb, lb)} @@`);
    for (const line of body) out.push(line);

    g = h + 1;
  }

  process.stdout.write(out.join('\n') + '\n');
}

main();
