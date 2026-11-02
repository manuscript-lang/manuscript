import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"

let FEE = 5
let BAD = "error: bad command\n"

# Parses a non-empty run of ASCII digits; returns -1 when the text is not digits only.
fn parse_digits(s: String) Int:
    if s.length() == 0: return -1

    var v = 0

    for c in s.scalar_values():
        if c < 48 or c > 57: return -1

        v = v * 10 + (c - 48)

    return v

type Ledger:
    balance: Map[String, Int]
    limit: Map[String, Int]
    ops: Map[String, Int]
    rejected: Map[String, Int]
    frozen: Map[String, Bool]
    fees: Int

impl Ledger:
    var fn blame(id: String) Unit:
        self.rejected.add(id.clone(), self.rejected.get(id).get(0) + 1)

    var fn bump_ops(id: String) Unit:
        self.ops.add(id.clone(), self.ops.get(id).get(0) + 1)

    # Fee charged by a debit of `amount` from `id` (independent of whether it succeeds).
    fn fee_for(id: String, amount: Int) Int:
        let bal = self.balance.get(id).get(0)
        if bal >= 0 and bal - amount < 0: return FEE

        return 0

    # Empty string when the debit is allowed, otherwise the error line (without newline).
    fn debit_error(id: String, amount: Int) String:
        let bal = self.balance.get(id).get(0)
        let fee = self.fee_for(id, amount)
        let nw = bal - amount - fee
        if nw < 0 - self.limit.get(id).get(0):
            return "error: overdraft limit exceeded {id}"

        return ""

    var fn do_open(id: String, lim: String) String:
        let l = parse_digits(lim)
        if l < 0: return "error: invalid limit\n"
        if self.balance.contains(id): return "error: account exists {id}\n"

        self.balance.add(id.clone(), 0)
        self.limit.add(id.clone(), l)
        self.ops.add(id.clone(), 0)
        self.rejected.add(id.clone(), 0)
        self.frozen.add(id.clone(), false)
        return "ok\n"

    var fn do_freeze(id: String, f: Bool) String:
        if not self.balance.contains(id): return "error: unknown account {id}\n"

        self.frozen.add(id.clone(), f)
        return "ok\n"

    var fn do_deposit(id: String, amt: String) String:
        if not self.balance.contains(id): return "error: unknown account {id}\n"

        let a = parse_digits(amt)

        if a <= 0:
            self.blame(id)
            return "error: invalid amount\n"

        if self.frozen.get(id).get(false):
            self.blame(id)
            return "error: account frozen {id}\n"

        let nb = self.balance.get(id).get(0) + a
        self.balance.add(id.clone(), nb)
        self.bump_ops(id)
        return "ok {nb}\n"

    var fn do_withdraw(id: String, amt: String) String:
        if not self.balance.contains(id): return "error: unknown account {id}\n"

        let a = parse_digits(amt)

        if a <= 0:
            self.blame(id)
            return "error: invalid amount\n"

        if self.frozen.get(id).get(false):
            self.blame(id)
            return "error: account frozen {id}\n"

        let err = self.debit_error(id, a)

        if err.length() > 0:
            self.blame(id)
            return "{err}\n"

        let fee = self.fee_for(id, a)
        let nb = self.balance.get(id).get(0) - a - fee
        self.balance.add(id.clone(), nb)
        self.fees += fee
        self.bump_ops(id)
        if fee > 0: return "ok {nb} fee={FEE}\n"

        return "ok {nb}\n"

    var fn do_transfer(from: String, to: String, amt: String) String:
        if not self.balance.contains(from): return "error: unknown account {from}\n"
        if not self.balance.contains(to): return "error: unknown account {to}\n"

        if from == to:
            self.blame(from)
            return "error: same account\n"

        let a = parse_digits(amt)

        if a <= 0:
            self.blame(from)
            return "error: invalid amount\n"

        if self.frozen.get(from).get(false):
            self.blame(from)
            return "error: account frozen {from}\n"

        if self.frozen.get(to).get(false):
            self.blame(to)
            return "error: account frozen {to}\n"

        let err = self.debit_error(from, a)

        if err.length() > 0:
            self.blame(from)
            return "{err}\n"

        let fee = self.fee_for(from, a)
        let nf = self.balance.get(from).get(0) - a - fee
        let nt = self.balance.get(to).get(0) + a
        self.balance.add(from.clone(), nf)
        self.balance.add(to.clone(), nt)
        self.fees += fee
        self.bump_ops(from)
        self.bump_ops(to)
        if fee > 0: return "ok {nf} {nt} fee={FEE}\n"

        return "ok {nf} {nt}\n"

    fn report() String:
        var ids = self.balance.keys()
        ids.sort()

        var out = ""
        var total = 0

        for id in ids:
            let b = self.balance.get(id).get(0)
            total += b

            let l = self.limit.get(id).get(0)
            let o = self.ops.get(id).get(0)
            let r = self.rejected.get(id).get(0)
            let fz = if self.frozen.get(id).get(false): "yes" else: "no"
            out += "{id} balance={b} limit={l} ops={o} rejected={r} frozen={fz}\n"

        out += "total balance={total} fees={self.fees}\n"
        return out

    var fn exec(t: List[String]) String:
        let cmd = t[0]
        let n = t.length()

        if cmd == "open":
            if n != 3: return BAD

            return self.do_open(t[1], t[2])

        if cmd == "deposit":
            if n != 3: return BAD

            return self.do_deposit(t[1], t[2])

        if cmd == "withdraw":
            if n != 3: return BAD

            return self.do_withdraw(t[1], t[2])

        if cmd == "transfer":
            if n != 4: return BAD

            return self.do_transfer(t[1], t[2], t[3])

        if cmd == "freeze":
            if n != 2: return BAD

            return self.do_freeze(t[1], true)

        if cmd == "unfreeze":
            if n != 2: return BAD

            return self.do_freeze(t[1], false)

        if cmd == "report":
            if n != 1: return BAD

            return self.report()

        return BAD

export fn main() Int:
    let lines = read_lines(stdin()).get()
    var ledger = Ledger(
        balance: Map[String, Int](), limit: Map[String, Int](), ops: Map[String, Int](),
        rejected: Map[String, Int](), frozen: Map[String, Bool](), fees: 0
    )

    for raw in lines:
        let toks = raw.replace("\t", " ").split(" ").filter(fn t: t.length() > 0)
        if toks.length() == 0: continue

        stdout().write(ledger.exec(toks)).get()

    return 0
