// CSV group sum. Reads stdin, writes stdout. See TASK.md.
import { readFileSync } from 'node:fs';

const AMOUNT_RE = /^(\d+)(\.\d{1,2})?$/;

// Parse one non-blank line into [category, amountCents] or null if invalid.
function parseLine(line: string): [string, bigint] | null {
  let category: string;
  let amountText: string;

  if (line.startsWith('"')) {
    // Quoted category: ends at the next double quote (no escaped quotes allowed).
    const close = line.indexOf('"', 1);
    if (close < 0) return null;
    if (line[close + 1] !== ',') return null;
    category = line.slice(1, close);
    amountText = line.slice(close + 2);
  } else {
    const comma = line.indexOf(',');
    if (comma < 0) return null;
    category = line.slice(0, comma);
    amountText = line.slice(comma + 1);
    // Exactly two fields: the amount itself must not contain a comma.
    if (amountText.includes(',')) return null;
  }

  if (category.length === 0) return null;
  const m = AMOUNT_RE.exec(amountText);
  if (!m) return null;

  const whole = BigInt(m[1]);
  const frac = m[2] ? m[2].slice(1) : '';
  const cents = whole * 100n + BigInt((frac + '00').slice(0, 2));
  return [category, cents];
}

function formatCents(cents: bigint): string {
  const whole = cents / 100n;
  const frac = (cents % 100n).toString().padStart(2, '0');
  return `${whole}.${frac}`;
}

function main(): void {
  const input = readFileSync(0, 'utf8');
  const lines = input.split('\n');

  const totals = new Map<string, bigint>();
  let skipped = 0;

  for (let raw of lines) {
    if (raw.endsWith('\r')) raw = raw.slice(0, -1);
    if (raw.trim() === '') continue; // blank lines are ignored
    const parsed = parseLine(raw);
    if (parsed === null) {
      skipped++;
      continue;
    }
    const [category, cents] = parsed;
    totals.set(category, (totals.get(category) ?? 0n) + cents);
  }

  // Byte order: compare the UTF-8 encodings.
  const keys = [...totals.keys()].sort((a, b) =>
    Buffer.compare(Buffer.from(a, 'utf8'), Buffer.from(b, 'utf8')),
  );

  const out: string[] = [];
  for (const k of keys) {
    out.push(`${k}: ${formatCents(totals.get(k)!)}`);
  }
  if (skipped > 0) out.push(`skipped: ${skipped}`);
  process.stdout.write(out.map((l) => l + '\n').join(''));
}

main();
