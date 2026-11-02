// Read stdin, write stdout. See TASK.md.
import { readFileSync } from 'node:fs';

function fail(msg: string): never {
  process.stdout.write(msg + '\n');
  process.exit(0);
}

function main(): void {
  const raw = readFileSync(0, 'utf8');
  let lines = raw.split('\n').map((l) => (l.endsWith('\r') ? l.slice(0, -1) : l));
  // Trailing empty lines are ignored.
  while (lines.length > 0 && lines[lines.length - 1] === '') lines.pop();

  // Rows as arrays of code points so columns are counted in characters.
  const grid: string[][] = lines.map((l) => Array.from(l));

  // 1. Bad characters, in reading order.
  for (let r = 0; r < grid.length; r++) {
    for (let c = 0; c < grid[r].length; c++) {
      const ch = grid[r][c];
      if (ch !== '#' && ch !== '.' && ch !== 'S' && ch !== 'E') {
        fail(`error: bad character at ${r + 1},${c + 1}`);
      }
    }
  }

  // 2. Ragged rows.
  const height = grid.length;
  const width = height > 0 ? grid[0].length : 0;
  for (const row of grid) {
    if (row.length !== width) fail('error: ragged grid');
  }

  // 3. Start cells.
  const starts: number[][] = [];
  const ends: number[][] = [];
  for (let r = 0; r < height; r++) {
    for (let c = 0; c < width; c++) {
      if (grid[r][c] === 'S') starts.push([r, c]);
      else if (grid[r][c] === 'E') ends.push([r, c]);
    }
  }
  if (starts.length === 0) fail('error: no start');
  if (starts.length > 1) fail('error: multiple starts');

  // 4. End cells.
  if (ends.length === 0) fail('error: no end');
  if (ends.length > 1) fail('error: multiple ends');

  // BFS from S over non-wall cells.
  const [sr, sc] = starts[0];
  const [er, ec] = ends[0];
  const dist = new Int32Array(height * width).fill(-1);
  const queue = new Int32Array(height * width);
  let head = 0;
  let tail = 0;
  dist[sr * width + sc] = 0;
  queue[tail++] = sr * width + sc;
  const dr = [-1, 1, 0, 0];
  const dc = [0, 0, -1, 1];
  while (head < tail) {
    const cur = queue[head++];
    const r = Math.floor(cur / width);
    const c = cur % width;
    if (r === er && c === ec) break;
    for (let k = 0; k < 4; k++) {
      const nr = r + dr[k];
      const nc = c + dc[k];
      if (nr < 0 || nr >= height || nc < 0 || nc >= width) continue;
      if (grid[nr][nc] === '#') continue;
      const idx = nr * width + nc;
      if (dist[idx] !== -1) continue;
      dist[idx] = dist[cur] + 1;
      queue[tail++] = idx;
    }
  }

  const d = dist[er * width + ec];
  process.stdout.write(d === -1 ? 'no path\n' : `${d}\n`);
}

main();
