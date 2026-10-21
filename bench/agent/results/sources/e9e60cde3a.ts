// Read stdin, write stdout. See TASK.md.
import { readFileSync } from "node:fs";

interface Entry {
  timestamp: string;
  level: string;
  method: string;
  path: string;
  status: number;
  latency: number;
}

const LEVELS = ["DEBUG", "INFO", "WARN", "ERROR"];
const METHODS = ["GET", "POST", "PUT", "DELETE"];

function parseLine(line: string): Entry | null {
  const fields = line.split(" ");
  if (fields.length !== 6) return null;
  const [timestamp, level, method, path, status, latency] = fields;
  if (timestamp === "") return null;
  if (!LEVELS.includes(level)) return null;
  if (!METHODS.includes(method)) return null;
  if (!path.startsWith("/")) return null;
  if (!/^[0-9]{3}$/.test(status)) return null;
  if (!/^[0-9]{1,9}$/.test(latency)) return null;
  return { timestamp, level, method, path, status: Number(status), latency: Number(latency) };
}

const input = readFileSync(0, "utf8");

const entries: Entry[] = [];
let malformed = 0;
for (const line of input.split("\n")) {
  if (line.trim() === "") continue;
  const entry = parseLine(line);
  if (entry === null) {
    malformed++;
  } else {
    entries.push(entry);
  }
}

const levelCounts = new Map<string, number>(LEVELS.map((level) => [level, 0]));
const statusCounts = { "2xx": 0, "3xx": 0, "4xx": 0, "5xx": 0, other: 0 };
const pathStats = new Map<string, { count: number; total: number }>();
let slowest: Entry | null = null;

for (const entry of entries) {
  levelCounts.set(entry.level, (levelCounts.get(entry.level) ?? 0) + 1);

  const firstDigit = Math.floor(entry.status / 100);
  if (firstDigit === 2) statusCounts["2xx"]++;
  else if (firstDigit === 3) statusCounts["3xx"]++;
  else if (firstDigit === 4) statusCounts["4xx"]++;
  else if (firstDigit === 5) statusCounts["5xx"]++;
  else statusCounts.other++;

  const stats = pathStats.get(entry.path) ?? { count: 0, total: 0 };
  stats.count++;
  stats.total += entry.latency;
  pathStats.set(entry.path, stats);

  // Strictly greater, so the earliest line wins ties.
  if (slowest === null || entry.latency > slowest.latency) slowest = entry;
}

const latencies = entries.map((entry) => entry.latency).sort((a, b) => a - b);
const n = latencies.length;
const p95 = n === 0 ? 0 : latencies[Math.floor((95 * n + 99) / 100) - 1];

const top = [...pathStats.entries()]
  .sort(([pathA, a], [pathB, b]) => {
    if (a.count !== b.count) return b.count - a.count;
    return pathA < pathB ? -1 : pathA > pathB ? 1 : 0;
  })
  .slice(0, 3);

const out: string[] = [];
out.push(`valid: ${entries.length}`);
out.push(`malformed: ${malformed}`);
for (const level of LEVELS) {
  out.push(`${level}: ${levelCounts.get(level)}`);
}
out.push(
  `status: 2xx=${statusCounts["2xx"]} 3xx=${statusCounts["3xx"]} 4xx=${statusCounts["4xx"]} 5xx=${statusCounts["5xx"]} other=${statusCounts.other}`,
);
out.push(`p95: ${p95}`);
if (slowest !== null) {
  out.push(`slowest: ${slowest.latency} ${slowest.method} ${slowest.path} ${slowest.timestamp}`);
}
out.push("top:");
for (const [path, stats] of top) {
  out.push(`${path} ${stats.count} avg=${Math.floor(stats.total / stats.count)}`);
}

process.stdout.write(out.join("\n") + "\n");
