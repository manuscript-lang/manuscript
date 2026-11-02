// Inventory and orders. Read stdin, write stdout. See TASK.md.

import { readFileSync } from 'node:fs';

interface Sku {
  stock: number;
  price: number; // cents
}

interface Line {
  sku: string;
  qty: number;
}

interface Order {
  status: 'placed' | 'shipped' | 'cancelled';
  lines: Line[];
  total: bigint; // cents
}

const skus = new Map<string, Sku>();
const orders = new Map<string, Order>();

const SKU_RE = /^[A-Z0-9-]+$/;
const ID_RE = /^[a-z0-9-]+$/;
const NUM_RE = /^[0-9]{1,7}$/;

// Returns the numeric value if the token is a valid number in [min, max], else null.
function parseNum(tok: string, min: number, max: number): number | null {
  if (!NUM_RE.test(tok)) return null;
  const n = Number(tok);
  if (n < min || n > max) return null;
  return n;
}

function parseQty(tok: string): number | null {
  return parseNum(tok, 1, 100000);
}

function parsePrice(tok: string): number | null {
  return parseNum(tok, 0, 10000000);
}

function money(cents: bigint): string {
  const neg = cents < 0n;
  const abs = neg ? -cents : cents;
  const dollars = abs / 100n;
  const rem = abs % 100n;
  return `${neg ? '-' : ''}${dollars}.${rem < 10n ? '0' : ''}${rem}`;
}

// Cost of a line in cents: qty * price, with 10% off (round half up) when qty >= 10.
function lineCost(qty: number, price: number): bigint {
  const base = BigInt(qty) * BigInt(price);
  if (qty >= 10) {
    return (base * 90n + 50n) / 100n;
  }
  return base;
}

function cmdStock(args: string[]): string {
  const [sku, q] = args;
  if (!SKU_RE.test(sku)) return 'error: bad sku';
  const qty = parseQty(q);
  if (qty === null) return 'error: bad quantity';
  const entry = skus.get(sku);
  if (entry) {
    entry.stock += qty;
  } else {
    skus.set(sku, { stock: qty, price: 0 });
  }
  return `ok ${sku} stock=${skus.get(sku)!.stock}`;
}

function cmdPrice(args: string[]): string {
  const [sku, c] = args;
  const cents = parsePrice(c);
  if (cents === null) return 'error: bad price';
  const entry = SKU_RE.test(sku) ? skus.get(sku) : undefined;
  if (!entry) return `error: unknown sku ${sku}`;
  entry.price = cents;
  return 'ok';
}

function cmdOrder(args: string[]): string {
  const id = args[0];
  if (!ID_RE.test(id)) return 'error: bad order id';

  // Argument syntax of every item comes before existence checks.
  const parsed: { token: string; sku: string; qty: number }[] = [];
  for (const token of args.slice(1)) {
    const parts = token.split(':');
    if (parts.length !== 2) return `error: bad item ${token}`;
    const [sku, q] = parts;
    if (!SKU_RE.test(sku)) return `error: bad item ${token}`;
    const qty = parseQty(q);
    if (qty === null) return `error: bad item ${token}`;
    parsed.push({ token, sku, qty });
  }

  if (orders.has(id)) return `error: order ${id} already exists`;

  const seen = new Set<string>();
  for (const item of parsed) {
    if (seen.has(item.sku)) return `error: duplicate sku ${item.sku}`;
    seen.add(item.sku);
    const entry = skus.get(item.sku);
    if (!entry) return `error: unknown sku ${item.sku}`;
    if (item.qty > entry.stock) {
      return `error: insufficient stock for ${item.sku} (have ${entry.stock}, need ${item.qty})`;
    }
  }

  // All checks passed: apply atomically.
  let total = 0n;
  const lines: Line[] = [];
  for (const item of parsed) {
    const entry = skus.get(item.sku)!;
    entry.stock -= item.qty;
    total += lineCost(item.qty, entry.price);
    lines.push({ sku: item.sku, qty: item.qty });
  }
  orders.set(id, { status: 'placed', lines, total });
  return `ok ${id} total=${money(total)}`;
}

function cmdCancel(args: string[]): string {
  const id = args[0];
  const order = ID_RE.test(id) ? orders.get(id) : undefined;
  if (!order) return `error: unknown order ${id}`;
  if (order.status === 'shipped') return `error: order ${id} already shipped`;
  if (order.status === 'cancelled') return `error: order ${id} already cancelled`;
  for (const line of order.lines) {
    skus.get(line.sku)!.stock += line.qty;
  }
  order.status = 'cancelled';
  return 'ok';
}

function cmdShip(args: string[]): string {
  const id = args[0];
  const order = ID_RE.test(id) ? orders.get(id) : undefined;
  if (!order) return `error: unknown order ${id}`;
  if (order.status === 'shipped') return `error: order ${id} already shipped`;
  if (order.status === 'cancelled') return `error: order ${id} is cancelled`;
  order.status = 'shipped';
  return 'ok';
}

function cmdReport(): string[] {
  const out: string[] = [];
  const reserved = new Map<string, number>();
  let placed = 0;
  let shipped = 0;
  let cancelled = 0;
  let revenue = 0n;
  for (const order of orders.values()) {
    if (order.status === 'placed') {
      placed++;
      for (const line of order.lines) {
        reserved.set(line.sku, (reserved.get(line.sku) ?? 0) + line.qty);
      }
    } else if (order.status === 'shipped') {
      shipped++;
      revenue += order.total;
    } else {
      cancelled++;
    }
  }
  const names = [...skus.keys()].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  for (const name of names) {
    const s = skus.get(name)!;
    out.push(
      `${name} stock=${s.stock} price=${money(BigInt(s.price))} reserved=${reserved.get(name) ?? 0}`,
    );
  }
  out.push(`orders placed=${placed} shipped=${shipped} cancelled=${cancelled}`);
  out.push(`revenue=${money(revenue)}`);
  return out;
}

function handle(line: string): string[] {
  const tokens = line.split(' ');
  const cmd = tokens[0];
  const args = tokens.slice(1);
  const n = tokens.length;
  switch (cmd) {
    case 'stock':
      return n !== 3 ? ['error: usage'] : [cmdStock(args)];
    case 'price':
      return n !== 3 ? ['error: usage'] : [cmdPrice(args)];
    case 'order':
      return n < 3 ? ['error: usage'] : [cmdOrder(args)];
    case 'cancel':
      return n !== 2 ? ['error: usage'] : [cmdCancel(args)];
    case 'ship':
      return n !== 2 ? ['error: usage'] : [cmdShip(args)];
    case 'report':
      return n !== 1 ? ['error: usage'] : cmdReport();
    default:
      return ['error: unknown command'];
  }
}

const input = readFileSync(0, 'utf8');
const outLines: string[] = [];
for (let raw of input.split('\n')) {
  if (raw.endsWith('\r')) raw = raw.slice(0, -1);
  if (/^ *$/.test(raw)) continue;
  for (const l of handle(raw)) outLines.push(l);
}
if (outLines.length > 0) {
  process.stdout.write(outLines.join('\n') + '\n');
}
