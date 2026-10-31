// Read stdin, write stdout. See TASK.md.
import readFileSync from 'node:fs';

function solve(input: string): string {
  const lines = input.split('\n');
  // Trailing empty lines are ignored; empty lines before the last row are rows of width 0.
  while (lines.length > 0 && lines[lines.length - 1] === '') lines.pop();

  // Columns are counted in characters (code points), not UTF-16 units.
  const rows = lines.map((line) => Array.from(line));

  for (let r = 0; r < rows.length; r++) {
    for (let c = 0; c < rows[r].length; c++) {
      const ch = rows[r][c];
      if (ch !== '#' && ch !== '.' && ch !== 'S' && ch !== 'E') {
        return `error: bad character at ${r + 1},${c + 1}`;
      }
    }
  }

  const width = rows.length > 0 ? rows[0].length : 0;
  if (rows.some((row) => row.length !== width)) return 'error: ragged grid';

  const starts: number[] = [];
  const ends: number[] = [];
  for (let r = 0; r < rows.length; r++) {
    for (let c = 0; c < width; c++) {
      if (rows[r][c] === 'S') starts.push(r * width + c);
      if (rows[r][c] === 'E') ends.push(r * width + c);
    }
  }
  if (starts.length === 0) return 'error: no start';
  if (starts.length > 1) return 'error: multiple starts';
  if (ends.length === 0) return 'error: no end';
  if (ends.length > 1) return 'error: multiple ends';

  const height = rows.length;
  const dist = new Int32Array(width * height).fill(-1);
  const queue: number[] = [starts[0]];
  dist[starts[0]] = 0;
  for (let head = 0; head < queue.length; head++) {
    const cur = queue[head];
    if (cur === ends[0]) return String(dist[cur]);
    const r = Math.floor(cur / width);
    const c = cur % width;
    const neighbors = [
      [r - 1, c],
      [r + 1, c],
      [r, c - 1],
      [r, c + 1],
    ];
    for (const [nr, nc] of neighbors) {
      if (nr < 0 || nr >= height || nc < 0 || nc >= width) continue;
      if (rows[nr][nc] === '#') continue;
      const next = nr * width + nc;
      if (dist[next] !== -1) continue;
      dist[next] = dist[cur] + 1;
      queue.push(next);
    }
  }
  return 'no path';
}

process.stdout.write(solve(readFileSync(0, 'utf8')) + '\n');
