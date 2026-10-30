// Read stdin, write stdout. See TASK.md.
import readFileSync from "node:fs";

const DAY_MS = 86_400_000;
const WINDOW_DAYS = 3000;
const MAX_COUNT = 20;

const FIELD_NAMES = ["bad minute", "bad hour", "bad day-of-month", "bad month", "bad day-of-week"];
const FIELD_RANGES: [number, number][] = [
  [0, 59],
  [0, 23],
  [1, 31],
  [1, 12],
  [0, 6],
];

function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

// Returns the sorted allowed values of one cron field, or null if the field is invalid.
function parseField(text: string, min: number, max: number): number[] | null {
  const allowed = new Set<number>();
  for (const item of text.split(",")) {
    const m = /^(\*|(\d{1,2})(-(\d{1,2}))?)(\/(\d{1,2}))?$/.exec(item);
    if (!m) return null;
    const [, head, aText, , bText, , stepText] = m;

    let lo: number;
    let hi: number;
    if (head === "*") {
      lo = min;
      hi = max;
    } else {
      lo = Number(aText);
      hi = bText === undefined ? lo : Number(bText);
      if (lo > hi) return null;
      if (bText === undefined && stepText !== undefined) return null;
      if (lo < min || hi > max) return null;
    }

    const step = stepText === undefined ? 1 : Number(stepText);
    if (step < 1) return null;

    for (let v = lo; v <= hi; v += step) allowed.add(v);
  }
  return [...allowed].sort((a, b) => a - b);
}

function formatDate(date: Date): string {
  const y = String(date.getUTCFullYear()).padStart(4, "0");
  const mo = String(date.getUTCMonth() + 1).padStart(2, "0");
  const d = String(date.getUTCDate()).padStart(2, "0");
  return `${y}-${mo}-${d}`;
}

function formatTime(hour: number, minute: number): string {
  return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
}

function processLine(line: string, lineNo: number): string[] {
  const prefix = `line ${lineNo}`;
  const tokens = line.split(" ");
  if (tokens.length !== 7) return [`${prefix}: error: bad line`];

  const [startText, countText, ...fieldTexts] = tokens;

  const sm = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(startText);
  const year = sm ? Number(sm[1]) : NaN;
  const month = sm ? Number(sm[2]) : NaN;
  const day = sm ? Number(sm[3]) : NaN;
  const hour = sm ? Number(sm[4]) : NaN;
  const minute = sm ? Number(sm[5]) : NaN;
  const startValid =
    sm !== null &&
    year >= 1970 &&
    year <= 2099 &&
    month >= 1 &&
    month <= 12 &&
    day >= 1 &&
    day <= daysInMonth(year, month) &&
    hour <= 23 &&
    minute <= 59;
  if (!startValid) return [`${prefix}: error: bad start`];

  const count = /^\d{1,2}$/.test(countText) ? Number(countText) : NaN;
  if (!(count >= 1 && count <= MAX_COUNT)) return [`${prefix}: error: bad count`];

  const fields: number[][] = [];
  for (let i = 0; i < fieldTexts.length; i++) {
    const [min, max] = FIELD_RANGES[i];
    const values = parseField(fieldTexts[i], min, max);
    if (values === null) return [`${prefix}: error: ${FIELD_NAMES[i]}`];
    fields.push(values);
  }
  const [minutes, hours, doms, months, dows] = fields;
  const domSet = new Set(doms);
  const monthSet = new Set(months);
  const dowSet = new Set(dows);

  const startDayMs = Date.UTC(year, month - 1, day);
  const startOfDay = hour * 60 + minute;
  const runs: Date[] = [];

  outer: for (let offset = 0; offset <= WINDOW_DAYS; offset++) {
    const dayMs = startDayMs + offset * DAY_MS;
    const date = new Date(dayMs);
    if (
      !monthSet.has(date.getUTCMonth() + 1) ||
      !domSet.has(date.getUTCDate()) ||
      !dowSet.has(date.getUTCDay())
    ) {
      continue;
    }
    for (const h of hours) {
      for (const m of minutes) {
        if (offset === 0 && h * 60 + m <= startOfDay) continue;
        runs.push(new Date(dayMs + (h * 60 + m) * 60_000));
        if (runs.length === count) break outer;
      }
    }
  }

  if (runs.length === 0) return [`${prefix}: never`];

  const out = [`${prefix}: ${runs.length} runs`];
  for (const run of runs) {
    out.push(`${formatDate(run)} ${formatTime(run.getUTCHours(), run.getUTCMinutes())}`);
  }
  return out;
}

const input = readFileSync(0, "utf8");
const lines = input.split("\n");
if (lines[lines.length - 1] === "") lines.pop();

const output: string[] = [];
lines.forEach((raw, i) => {
  const line = raw.endsWith("\r") ? raw.slice(0, -1) : raw;
  if (/^ *$/.test(line)) return;
  output.push(...processLine(line, i + 1));
});

if (output.length > 0) process.stdout.write(output.join("\n") + "\n");
