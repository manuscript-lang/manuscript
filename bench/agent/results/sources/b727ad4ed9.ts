// Log analyzer: reads a web-server log on stdin, prints a report. See TASK.md.

const LEVELS = ['DEBUG', 'INFO', 'WARN', 'ERROR'];
const METHODS = new Set(['GET', 'POST', 'PUT', 'DELETE']);

interface Valid {
  level: string;
  method: string;
  path: string;
  status: string;
  latency: number;
  timestamp: string;
  index: number;
}

function parseLine(line: string): Valid | null {
  const f = line.split(' ');
  if (f.length !== 6) return null;
  const [timestamp, level, method, path, status, latency] = f;
  if (timestamp === '') return null;
  if (!LEVELS.includes(level)) return null;
  if (!METHODS.has(method)) return null;
  if (path === '' || path[0] !== '/') return null;
  if (!/^[0-9]{3}$/.test(status)) return null;
  if (!/^[0-9]{1,9}$/.test(latency)) return null;
  return { level, method, path, status, latency: Number(latency), timestamp, index: 0 };
}

function isBlank(line: string): boolean {
  return /^[ \t\r\n\f\v]*$/.test(line);
}

function byteCompare(a: string, b: string): number {
  return Buffer.compare(Buffer.from(a, 'utf8'), Buffer.from(b, 'utf8'));
}

function main(): void {
  const input = require('node:fs').readFileSync(0, 'utf8') as string;
  const lines = input.split('\n');
  // A trailing newline produces an empty final element, which is blank and skipped anyway.

  const valid: Valid[] = [];
  let malformed = 0;
  for (const line of lines) {
    if (isBlank(line)) continue;
    const rec = parseLine(line);
    if (rec === null) {
      malformed++;
    } else {
      rec.index = valid.length;
      valid.push(rec);
    }
  }

  const levelCounts = new Map<string, number>(LEVELS.map((l) => [l, 0]));
  const status = { '2': 0, '3': 0, '4': 0, '5': 0, other: 0 } as Record<string, number>;
  const pathStats = new Map<string, { count: number; total: number }>();
  for (const r of valid) {
    levelCounts.set(r.level, (levelCounts.get(r.level) ?? 0) + 1);
    const d = r.status[0];
    if (d in status && d !== 'other') status[d]++;
    else status.other++;
    const ps = pathStats.get(r.path) ?? { count: 0, total: 0 };
    ps.count++;
    ps.total += r.latency;
    pathStats.set(r.path, ps);
  }

  const out: string[] = [];
  out.push(`valid: ${valid.length}`);
  out.push(`malformed: ${malformed}`);
  for (const l of LEVELS) out.push(`${l}: ${levelCounts.get(l)}`);
  out.push(
    `status: 2xx=${status['2']} 3xx=${status['3']} 4xx=${status['4']} 5xx=${status['5']} other=${status.other}`,
  );

  const n = valid.length;
  if (n === 0) {
    out.push('p95: 0');
  } else {
    const sorted = valid.map((r) => r.latency).sort((a, b) => a - b);
    const rank = Math.floor((95 * n + 99) / 100);
    out.push(`p95: ${sorted[rank - 1]}`);

    let slowest = valid[0];
    for (const r of valid) if (r.latency > slowest.latency) slowest = r;
    out.push(`slowest: ${slowest.latency} ${slowest.method} ${slowest.path} ${slowest.timestamp}`);
  }

  out.push('top:');
  const ranked = [...pathStats.entries()].sort((a, b) => {
    if (a[1].count !== b[1].count) return b[1].count - a[1].count;
    return byteCompare(a[0], b[0]);
  });
  for (const [path, ps] of ranked.slice(0, 3)) {
    out.push(`${path} ${ps.count} avg=${Math.floor(ps.total / ps.count)}`);
  }

  process.stdout.write(out.join('\n') + '\n');
}

main();
