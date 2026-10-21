// Read stdin, write stdout. See TASK.md.
import * as fs from 'node:fs';

type Sku = { stock: number; price: number };
type Line = { sku: string; qty: number; record: Sku };
type Order = { lines: Line[]; total: number; status: 'placed' | 'shipped' | 'cancelled' };

const skus = new Map<string, Sku>();
const orders = new Map<string, Order>();

const SKU = /^[A-Z0-9-]+$/;
const ORDER_ID = /^[a-z0-9-]+$/;
const NUMBER = /^[0-9]{1,7}$/;
const ITEM = /^([A-Z0-9-]+):([0-9]{1,7})$/;

function parseNumber(token: string): number | null {
  return NUMBER.test(token) ? Number(token) : null;
}

function quantity(token: string): number | null {
  const n = parseNumber(token);
  return n !== null && n >= 1 && n <= 100000 ? n : null;
}

function money(cents: number): string {
  return `${Math.floor(cents / 100)}.${String(cents % 100).padStart(2, '0')}`;
}

function lineCost(qty: number, unit: number): number {
  const gross = qty * unit;
  // round_half_up(gross * 90 / 100) for the 10% bulk discount
  return qty >= 10 ? Math.floor((gross * 90 + 50) / 100) : gross;
}

function stockCmd([sku, qtyText]: string[]): string {
  if (!SKU.test(sku)) return 'error: bad sku';
  const qty = quantity(qtyText);
  if (qty === null) return 'error: bad quantity';
  const record = skus.get(sku) ?? { stock: 0, price: 0 };
  record.stock += qty;
  skus.set(sku, record);
  return `ok ${sku} stock=${record.stock}`;
}

function priceCmd([sku, cents]: string[]): string {
  // 7 digits tops out at 9999999, so any well-formed price is within range
  const unit = parseNumber(cents);
  if (unit === null) return 'error: bad price';
  const record = skus.get(sku);
  if (!record) return `error: unknown sku ${sku}`;
  record.price = unit;
  return 'ok';
}

function orderCmd([id, ...items]: string[]): string {
  if (!ORDER_ID.test(id)) return 'error: bad order id';

  const parsed: { sku: string; qty: number }[] = [];
  for (const token of items) {
    const match = ITEM.exec(token);
    const qty = match ? quantity(match[2]) : null;
    if (!match || qty === null) return `error: bad item ${token}`;
    parsed.push({ sku: match[1], qty });
  }

  if (orders.has(id)) return `error: order ${id} already exists`;

  const lines: Line[] = [];
  const seen = new Set<string>();
  for (const { sku, qty } of parsed) {
    if (seen.has(sku)) return `error: duplicate sku ${sku}`;
    seen.add(sku);
    const record = skus.get(sku);
    if (!record) return `error: unknown sku ${sku}`;
    if (qty > record.stock) {
      return `error: insufficient stock for ${sku} (have ${record.stock}, need ${qty})`;
    }
    lines.push({ sku, qty, record });
  }

  let total = 0;
  for (const { qty, record } of lines) {
    record.stock -= qty;
    total += lineCost(qty, record.price);
  }
  orders.set(id, { lines, total, status: 'placed' });
  return `ok ${id} total=${money(total)}`;
}

function cancelCmd([id]: string[]): string {
  const order = orders.get(id);
  if (!order) return `error: unknown order ${id}`;
  if (order.status === 'shipped') return `error: order ${id} already shipped`;
  if (order.status === 'cancelled') return `error: order ${id} already cancelled`;
  for (const { qty, record } of order.lines) record.stock += qty;
  order.status = 'cancelled';
  return 'ok';
}

function shipCmd([id]: string[]): string {
  const order = orders.get(id);
  if (!order) return `error: unknown order ${id}`;
  if (order.status === 'shipped') return `error: order ${id} already shipped`;
  if (order.status === 'cancelled') return `error: order ${id} is cancelled`;
  order.status = 'shipped';
  return 'ok';
}

function reportCmd(): string[] {
  const reserved = new Map<string, number>();
  let placed = 0;
  let shipped = 0;
  let cancelled = 0;
  let revenue = 0;
  for (const order of orders.values()) {
    if (order.status === 'placed') {
      placed++;
      for (const { sku, qty } of order.lines) reserved.set(sku, (reserved.get(sku) ?? 0) + qty);
    } else if (order.status === 'shipped') {
      shipped++;
      revenue += order.total;
    } else {
      cancelled++;
    }
  }

  const lines: string[] = [];
  for (const sku of [...skus.keys()].sort()) {
    const record = skus.get(sku);
    lines.push(
      `${sku} stock=${record.stock} price=${money(record.price)} reserved=${reserved.get(sku) ?? 0}`,
    );
  }
  lines.push(`orders placed=${placed} shipped=${shipped} cancelled=${cancelled}`);
  lines.push(`revenue=${money(revenue)}`);
  return lines;
}

function run(line: string): string[] {
  const [name, ...args] = line.split(' ');
  const usage = ['error: usage'];
  switch (name) {
    case 'stock':
      return args.length === 2 ? [stockCmd(args)] : usage;
    case 'price':
      return args.length === 2 ? [priceCmd(args)] : usage;
    case 'order':
      return args.length >= 2 ? [orderCmd(args)] : usage;
    case 'cancel':
      return args.length === 1 ? [cancelCmd(args)] : usage;
    case 'ship':
      return args.length === 1 ? [shipCmd(args)] : usage;
    case 'report':
      return args.length === 0 ? reportCmd() : usage;
    default:
      return ['error: unknown command'];
  }
}

const input = fs.readFileSync(0, 'utf8');
let output = '';
for (const raw of input.split('\n')) {
  const line = raw.endsWith('\r') ? raw.slice(0, -1) : raw;
  if (/^ *$/.test(line)) continue;
  for (const out of run(line)) output += out + '\n';
}
process.stdout.write(output);
