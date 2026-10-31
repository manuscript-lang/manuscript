import { readFileSync } from 'node:fs';

const DAY_MS = 86400000;
const WINDOW_DAYS = 3000;

interface Range { min: number; max: number }
const MINUTE: Range = { min: 0, max: 59 };
const HOUR: Range = { min: 0, max: 23 };
const DOM: Range = { min: 1, max: 31 };
const MONTH: Range = { min: 1, max: 12 };
const DOW: Range = { min: 0, max: 6 };

const NUM_RE = /^[0-9]{1,2}$/;

function parseNum(s: string, r: Range): number | null {
  if (!NUM_RE.test(s)) return null;
  const v = Number(s);
  return v >= r.min && v <= r.max ? v : null;
}

// Returns a membership table for the field, or null if the field is invalid.
function parseField(text: string, r: Range): boolean[] | null {
  const set: boolean[] = new Array(r.max + 1).fill(false);
  for (const item of text.split(',')) {
    let body = item;
    let step = 1;
    const slash = item.indexOf('/');
    if (slash >= 0) {
      body = item.slice(0, slash);
      const s = item.slice(slash + 1);
      if (!NUM_RE.test(s)) return null;
      step = Number(s);
      if (step < 1) return null;
    }
    let lo: number;
    let hi: number;
    if (body === '*') {
      lo = r.min;
      hi = r.max;
    } else if (body.includes('-')) {
      const parts = body.split('-');
      if (parts.length !== 2) return null;
      const a = parseNum(parts[0], r);
      const b = parseNum(parts[1], r);
      if (a === null || b === null || a > b) return null;
      lo = a;
      hi = b;
    } else {
      // A single number is only valid without a step.
      if (slash >= 0) return null;
      const a = parseNum(body, r);
      if (a === null) return null;
      lo = a;
      hi = a;
    }
    for (let v = lo; v <= hi; v += step) set[v] = true;
  }
  return set;
}

function isLeap(y: number): boolean {
  return (y % 4 === 0 && y % 100 !== 0) || y % 400 === 0;
}

function daysInMonth(y: number, m: number): number {
  if (m === 2) return isLeap(y) ? 29 : 28;
  return [4, 6, 9, 11].includes(m) ? 30 : 31;
}

interface Start { y: number; mo: number; d: number; h: number; mi: number }

function parseStart(s: string): Start | null {
  const m = /^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2})$/.exec(s);
  if (!m) return null;
  const y = Number(m[1]);
  const mo = Number(m[2]);
  const d = Number(m[3]);
  const h = Number(m[4]);
  const mi = Number(m[5]);
  if (y < 1970 || y > 2099) return null;
  if (mo < 1 || mo > 12) return null;
  if (d < 1 || d > daysInMonth(y, mo)) return null;
  if (h > 23 || mi > 59) return null;
  return { y, mo, d, h, mi };
}

function pad(n: number, w: number): string {
  return String(n).padStart(w, '0');
}

function formatRun(dayNum: number, h: number, mi: number): string {
  const dt = new Date(dayNum * DAY_MS);
  return `${pad(dt.getUTCFullYear(), 4)}-${pad(dt.getUTCMonth() + 1, 2)}-${pad(dt.getUTCDate(), 2)} ${pad(h, 2)}:${pad(mi, 2)}`;
}

function solveLine(lineNo: number, raw: string): string[] {
  const tokens = raw.split(' ');
  const err = (msg: string) => [`line ${lineNo}: error: ${msg}`];
  if (tokens.length !== 7) return err('bad line');

  const [startTok, countTok, minTok, hourTok, domTok, monTok, dowTok] = tokens;

  const start = parseStart(startTok);
  if (!start) return err('bad start');

  if (!NUM_RE.test(countTok) || Number(countTok) < 1 || Number(countTok) > 20) {
    return err('bad count');
  }
  const count = Number(countTok);

  const minSet = parseField(minTok, MINUTE);
  if (!minSet) return err('bad minute');
  const hourSet = parseField(hourTok, HOUR);
  if (!hourSet) return err('bad hour');
  const domSet = parseField(domTok, DOM);
  if (!domSet) return err('bad day-of-month');
  const monSet = parseField(monTok, MONTH);
  if (!monSet) return err('bad month');
  const dowSet = parseField(dowTok, DOW);
  if (!dowSet) return err('bad day-of-week');

  const hours: number[] = [];
  for (let h = 0; h <= 23; h++) if (hourSet[h]) hours.push(h);
  const minutes: number[] = [];
  for (let m = 0; m <= 59; m++) if (minSet[m]) minutes.push(m);

  const startDay = Math.round(Date.UTC(start.y, start.mo - 1, start.d) / DAY_MS);
  const runs: string[] = [];

  for (let k = 0; k <= WINDOW_DAYS && runs.length < count; k++) {
    const dayNum = startDay + k;
    const dt = new Date(dayNum * DAY_MS);
    const mon = dt.getUTCMonth() + 1;
    const dom = dt.getUTCDate();
    const dow = dt.getUTCDay();
    if (!monSet[mon] || !domSet[dom] || !dowSet[dow]) continue;

    for (const h of hours) {
      for (const mi of minutes) {
        if (runs.length >= count) break;
        if (k === 0 && (h < start.h || (h === start.h && mi <= start.mi))) continue;
        runs.push(formatRun(dayNum, h, mi));
      }
      if (runs.length >= count) break;
    }
  }

  if (runs.length === 0) return [`line ${lineNo}: never`];
  return [`line ${lineNo}: ${runs.length} runs`, ...runs];
}

const input = readFileSync(0, 'utf8');
const lines = input.split('\n');
const out: string[] = [];
for (let i = 0; i < lines.length; i++) {
  const raw = lines[i].endsWith('\r') ? lines[i].slice(0, -1) : lines[i];
  if (/^ *$/.test(raw)) continue;
  out.push(...solveLine(i + 1, raw));
}
if (out.length > 0) process.stdout.write(out.join('\n') + '\n');
