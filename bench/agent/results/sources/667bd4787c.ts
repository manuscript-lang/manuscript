// Read stdin, write stdout. See TASK.md.
import { readFileSync } from 'node:fs';

const AMOUNT = /^\d+(\.\d{1,2})?$/;

// Returns [category, cents] for a valid record, or null if the line is invalid.
function parseRecord(line: string): [string, bigint] | null {
  let category: string;
  let amount: string;
  if (line.startsWith('"')) {
    const close = line.indexOf('"', 1);
    if (close === -1 || line[close + 1] !== ',') return null;
    category = line.slice(1, close);
    amount = line.slice(close + 2);
  } else {
    const comma = line.indexOf(',');
    if (comma === -1) return null;
    category = line.slice(0, comma);
    amount = line.slice(comma + 1);
  }
  if (category === '' || !AMOUNT.test(amount)) return null;

  const [whole, frac = ''] = amount.split('.');
  return [category, BigInt(whole) * 100n + BigInt(frac.padEnd(2, '0'))];
}

const totals = new Map<string, bigint>();
let skipped = 0;

for (const raw of readFileSync(0, 'utf8').split('\n')) {
  const line = raw.endsWith('\r') ? raw.slice(0, -1) : raw;
  if (line === '') continue;

  const record = parseRecord(line);
  if (record === null) {
    skipped++;
    continue;
  }
  const [category, cents] = record;
  totals.set(category, (totals.get(category) ?? 0n) + cents);
}

// Byte order: compare UTF-8 encodings, not UTF-16 code units.
const categories = [...totals.keys()].sort((a, b) =>
  Buffer.compare(Buffer.from(a, 'utf8'), Buffer.from(b, 'utf8')),
);

const out: string[] = [];
for (const category of categories) {
  const cents = totals.get(category)!;
  const whole = cents / 100n;
  const frac = (cents % 100n).toString().padStart(2, '0');
  out.push(`${category}: ${whole}.${frac}`);
}
if (skipped > 0) out.push(`skipped: ${skipped}`);

if (out.length > 0) process.stdout.write(out.join('\n') + '\n');
