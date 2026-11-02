// Read stdin, write stdout. See TASK.md.
import { readFileSync } from 'node:fs';

interface Account {
  id: string;
  balance: bigint;
  limit: bigint;
  ops: number;
  rejected: number;
  frozen: boolean;
}

const FEE = 5n;
const accounts = new Map<string, Account>();
let feesTotal = 0n;
const out: string[] = [];

const isDigits = (s: string): boolean => /^[0-9]+$/.test(s);

// Valid amount: non-empty ASCII digits with value > 0.
function parseAmount(s: string): bigint | null {
  if (!isDigits(s)) return null;
  const v = BigInt(s);
  return v > 0n ? v : null;
}

function blame(acct: Account): void {
  acct.rejected += 1;
}

// Step 5 for withdraw / transfer FROM. Returns the new balance and fee, or an error.
function debit(acct: Account, amount: bigint): { err: string } | { newBal: bigint; fee: bigint } {
  let newBal = acct.balance - amount;
  let fee = 0n;
  if (acct.balance >= 0n && newBal < 0n) {
    fee = FEE;
    newBal -= FEE;
  }
  if (newBal < -acct.limit) {
    return { err: `error: overdraft limit exceeded ${acct.id}` };
  }
  return { newBal, fee };
}

function feeSuffix(fee: bigint): string {
  return fee > 0n ? ` fee=${fee}` : '';
}

function run(tokens: string[]): string | null {
  if (tokens.length === 0) return null;
  const cmd = tokens[0];
  const args = tokens.slice(1);
  const bad = 'error: bad command';

  switch (cmd) {
    case 'open': {
      if (args.length !== 2) return bad;
      const [id, limit] = args;
      if (!isDigits(limit)) return 'error: invalid limit';
      if (accounts.has(id)) return `error: account exists ${id}`;
      accounts.set(id, {
        id,
        balance: 0n,
        limit: BigInt(limit),
        ops: 0,
        rejected: 0,
        frozen: false,
      });
      return 'ok';
    }

    case 'freeze':
    case 'unfreeze': {
      if (args.length !== 1) return bad;
      const acct = accounts.get(args[0]);
      if (!acct) return `error: unknown account ${args[0]}`;
      acct.frozen = cmd === 'freeze';
      return 'ok';
    }

    case 'deposit': {
      if (args.length !== 2) return bad;
      const [id, amountStr] = args;
      const acct = accounts.get(id);
      if (!acct) return `error: unknown account ${id}`;
      const amount = parseAmount(amountStr);
      if (amount === null) {
        blame(acct);
        return 'error: invalid amount';
      }
      if (acct.frozen) {
        blame(acct);
        return `error: account frozen ${id}`;
      }
      acct.balance += amount;
      acct.ops += 1;
      return `ok ${acct.balance}`;
    }

    case 'withdraw': {
      if (args.length !== 2) return bad;
      const [id, amountStr] = args;
      const acct = accounts.get(id);
      if (!acct) return `error: unknown account ${id}`;
      const amount = parseAmount(amountStr);
      if (amount === null) {
        blame(acct);
        return 'error: invalid amount';
      }
      if (acct.frozen) {
        blame(acct);
        return `error: account frozen ${id}`;
      }
      const r = debit(acct, amount);
      if ('err' in r) {
        blame(acct);
        return r.err;
      }
      acct.balance = r.newBal;
      feesTotal += r.fee;
      acct.ops += 1;
      return `ok ${acct.balance}${feeSuffix(r.fee)}`;
    }

    case 'transfer': {
      if (args.length !== 3) return bad;
      const [fromId, toId, amountStr] = args;
      const from = accounts.get(fromId);
      if (!from) return `error: unknown account ${fromId}`;
      const to = accounts.get(toId);
      if (!to) return `error: unknown account ${toId}`;
      if (from === to) {
        blame(from);
        return 'error: same account';
      }
      const amount = parseAmount(amountStr);
      if (amount === null) {
        blame(from);
        return 'error: invalid amount';
      }
      if (from.frozen) {
        blame(from);
        return `error: account frozen ${fromId}`;
      }
      if (to.frozen) {
        blame(to);
        return `error: account frozen ${toId}`;
      }
      const r = debit(from, amount);
      if ('err' in r) {
        blame(from);
        return r.err;
      }
      from.balance = r.newBal;
      to.balance += amount;
      feesTotal += r.fee;
      from.ops += 1;
      to.ops += 1;
      return `ok ${from.balance} ${to.balance}${feeSuffix(r.fee)}`;
    }

    case 'report': {
      if (args.length !== 0) return bad;
      const ids = [...accounts.keys()].sort((a, b) =>
        Buffer.compare(Buffer.from(a, 'utf8'), Buffer.from(b, 'utf8')),
      );
      let total = 0n;
      for (const id of ids) {
        const a = accounts.get(id)!;
        total += a.balance;
        out.push(
          `${a.id} balance=${a.balance} limit=${a.limit} ops=${a.ops} rejected=${a.rejected} frozen=${a.frozen ? 'yes' : 'no'}`,
        );
      }
      out.push(`total balance=${total} fees=${feesTotal}`);
      return null;
    }

    default:
      return bad;
  }
}

const input = readFileSync(0, 'utf8');
for (const rawLine of input.split('\n')) {
  const line = rawLine.endsWith('\r') ? rawLine.slice(0, -1) : rawLine;
  const tokens = line.split(/[ \t]+/).filter((t) => t.length > 0);
  const res = run(tokens);
  if (res !== null) out.push(res);
}

if (out.length > 0) {
  process.stdout.write(out.join('\n') + '\n');
}
