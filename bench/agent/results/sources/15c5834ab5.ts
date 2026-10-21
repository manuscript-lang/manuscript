// Read stdin, write stdout. See TASK.md.
import { readFileSync } from 'node:fs';

type Account = {
  id: string;
  balance: bigint;
  limit: bigint;
  ops: number;
  rejected: number;
  frozen: boolean;
};

const FEE = 5n;
const accounts = new Map<string, Account>();
let fees = 0n;
const out: string[] = [];

function isDigits(s: string): boolean {
  return /^[0-9]+$/.test(s);
}

// Returns the amount, or null when it is not a positive digit string.
function parseAmount(s: string): bigint | null {
  if (!isDigits(s)) return null;
  const v = BigInt(s);
  return v > 0n ? v : null;
}

function blame(acc: Account): void {
  acc.rejected++;
}

// Applies the overdraft rule for a debit of `amount` from `acc`. Returns the new
// balance and fee charged, or null when the overdraft limit would be exceeded.
function debit(acc: Account, amount: bigint): { balance: bigint; fee: bigint } | null {
  let next = acc.balance - amount;
  let fee = 0n;
  if (acc.balance >= 0n && next < 0n) {
    fee = FEE;
    next -= FEE;
  }
  if (next < -acc.limit) return null;
  return { balance: next, fee };
}

function feeSuffix(fee: bigint): string {
  return fee > 0n ? ` fee=${fee}` : '';
}

function cmdOpen(id: string, limit: string): void {
  if (!isDigits(limit)) return out.push('error: invalid limit');
  if (accounts.has(id)) return out.push(`error: account exists ${id}`);
  accounts.set(id, { id, balance: 0n, limit: BigInt(limit), ops: 0, rejected: 0, frozen: false });
  out.push('ok');
}

function cmdFreeze(id: string, frozen: boolean): void {
  const acc = accounts.get(id);
  if (!acc) return out.push(`error: unknown account ${id}`);
  acc.frozen = frozen;
  out.push('ok');
}

function cmdDeposit(id: string, amountText: string): void {
  const acc = accounts.get(id);
  if (!acc) return out.push(`error: unknown account ${id}`);
  const amount = parseAmount(amountText);
  if (amount === null) {
    blame(acc);
    return out.push('error: invalid amount');
  }
  if (acc.frozen) {
    blame(acc);
    return out.push(`error: account frozen ${id}`);
  }
  acc.balance += amount;
  acc.ops++;
  out.push(`ok ${acc.balance}`);
}

function cmdWithdraw(id: string, amountText: string): void {
  const acc = accounts.get(id);
  if (!acc) return out.push(`error: unknown account ${id}`);
  const amount = parseAmount(amountText);
  if (amount === null) {
    blame(acc);
    return out.push('error: invalid amount');
  }
  if (acc.frozen) {
    blame(acc);
    return out.push(`error: account frozen ${id}`);
  }
  const result = debit(acc, amount);
  if (result === null) {
    blame(acc);
    return out.push(`error: overdraft limit exceeded ${id}`);
  }
  acc.balance = result.balance;
  fees += result.fee;
  acc.ops++;
  out.push(`ok ${acc.balance}${feeSuffix(result.fee)}`);
}

function cmdTransfer(fromId: string, toId: string, amountText: string): void {
  const from = accounts.get(fromId);
  if (!from) return out.push(`error: unknown account ${fromId}`);
  const to = accounts.get(toId);
  if (!to) return out.push(`error: unknown account ${toId}`);
  if (from === to) {
    blame(from);
    return out.push('error: same account');
  }
  const amount = parseAmount(amountText);
  if (amount === null) {
    blame(from);
    return out.push('error: invalid amount');
  }
  if (from.frozen) {
    blame(from);
    return out.push(`error: account frozen ${fromId}`);
  }
  if (to.frozen) {
    blame(to);
    return out.push(`error: account frozen ${toId}`);
  }
  const result = debit(from, amount);
  if (result === null) {
    blame(from);
    return out.push(`error: overdraft limit exceeded ${fromId}`);
  }
  from.balance = result.balance;
  fees += result.fee;
  to.balance += amount;
  from.ops++;
  to.ops++;
  out.push(`ok ${from.balance} ${to.balance}${feeSuffix(result.fee)}`);
}

function cmdReport(): void {
  const ids = [...accounts.keys()].sort((a, b) => Buffer.compare(Buffer.from(a), Buffer.from(b)));
  let total = 0n;
  for (const id of ids) {
    const acc = accounts.get(id)!;
    total += acc.balance;
    out.push(
      `${id} balance=${acc.balance} limit=${acc.limit} ops=${acc.ops} rejected=${acc.rejected} frozen=${acc.frozen ? 'yes' : 'no'}`,
    );
  }
  out.push(`total balance=${total} fees=${fees}`);
}

const BAD = 'error: bad command';

function run(tokens: string[]): void {
  const [cmd, ...args] = tokens;
  switch (cmd) {
    case 'open':
      return args.length === 2 ? cmdOpen(args[0], args[1]) : out.push(BAD);
    case 'deposit':
      return args.length === 2 ? cmdDeposit(args[0], args[1]) : out.push(BAD);
    case 'withdraw':
      return args.length === 2 ? cmdWithdraw(args[0], args[1]) : out.push(BAD);
    case 'transfer':
      return args.length === 3 ? cmdTransfer(args[0], args[1], args[2]) : out.push(BAD);
    case 'freeze':
      return args.length === 1 ? cmdFreeze(args[0], true) : out.push(BAD);
    case 'unfreeze':
      return args.length === 1 ? cmdFreeze(args[0], false) : out.push(BAD);
    case 'report':
      return args.length === 0 ? cmdReport() : out.push(BAD);
    default:
      return out.push(BAD);
  }
}

const input = readFileSync(0, 'utf8');
for (const rawLine of input.split('\n')) {
  const line = rawLine.endsWith('\r') ? rawLine.slice(0, -1) : rawLine;
  const tokens = line.split(/[ \t]+/).filter((t) => t !== '');
  if (tokens.length === 0) continue;
  run(tokens);
}
if (out.length > 0) process.stdout.write(out.join('\n') + '\n');
