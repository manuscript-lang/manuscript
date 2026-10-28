import stdin from "@std/io.ms"
import stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"

type Ledger:
    balance: Map[String, Int]
    limit: Map[String, Int]
    ops: Map[String, Int]
    rejected: Map[String, Int]
    frozen: Map[String, Bool]
    fees: Int

# Value of a plain digit token, or -1 when it is not one (signs, decimals, letters, overflow).
fn number(s: String) Int:
    if s.contains("+") or s.contains("-"): return -1
    if let v = s.parse_int(): return v

    return -1

# Overdraft fee charged when a debit takes a non-negative balance below zero.
fn fee_for(balance: Int, amount: Int) Int:
    if balance >= 0 and balance - amount < 0: return 5

    return 0

fn tokens(line: String) List[String]:
    var out = List[String]()
    for part in line.replace("\t", " ").replace("\r", " ").split(" "):
        if part.length() > 0: out.append(part)
    return out

impl Ledger:
    var fn blame(id: String) Unit:
        self.rejected.update(id, 0, fn(n: Int) Int: n + 1)

    var fn bump(id: String) Unit:
        self.ops.update(id, 0, fn(n: Int) Int: n + 1)

    var fn do_open(id: String, text: String) String:
        let lim = number(text)
        if lim < 0: return "error: invalid limit"
        if self.balance.contains(id): return "error: account exists {id}"

        self.balance[id.clone()] = 0
        self.limit[id.clone()] = lim
        self.ops[id.clone()] = 0
        self.rejected[id.clone()] = 0
        self.frozen[id.clone()] = false
        return "ok"

    var fn do_deposit(id: String, text: String) String:
        if not self.balance.contains(id): return "error: unknown account {id}"

        let amt = number(text)

        if amt <= 0:
            self.blame(id)
            return "error: invalid amount"

        if self.frozen.get_or(id, false):
            self.blame(id)
            return "error: account frozen {id}"

        let after = self.balance.get_or(id, 0) + amt
        self.balance[id.clone()] = after
        self.bump(id)
        return "ok {after}"

    var fn do_withdraw(id: String, text: String) String:
        if not self.balance.contains(id): return "error: unknown account {id}"

        let amt = number(text)

        if amt <= 0:
            self.blame(id)
            return "error: invalid amount"

        if self.frozen.get_or(id, false):
            self.blame(id)
            return "error: account frozen {id}"

        let before = self.balance.get_or(id, 0)
        let fee = fee_for(before, amt)
        let after = before - amt - fee

        if after < -self.limit.get_or(id, 0):
            self.blame(id)
            return "error: overdraft limit exceeded {id}"

        self.balance[id.clone()] = after
        self.bump(id)
        self.fees += fee
        if fee > 0: return "ok {after} fee=5"

        return "ok {after}"

    var fn do_transfer(from: String, to: String, text: String) String:
        if not self.balance.contains(from): return "error: unknown account {from}"
        if not self.balance.contains(to): return "error: unknown account {to}"

        if from == to:
            self.blame(from)
            return "error: same account"

        let amt = number(text)

        if amt <= 0:
            self.blame(from)
            return "error: invalid amount"

        if self.frozen.get_or(from, false):
            self.blame(from)
            return "error: account frozen {from}"

        if self.frozen.get_or(to, false):
            self.blame(to)
            return "error: account frozen {to}"

        let before = self.balance.get_or(from, 0)
        let fee = fee_for(before, amt)
        let after = before - amt - fee

        if after < -self.limit.get_or(from, 0):
            self.blame(from)
            return "error: overdraft limit exceeded {from}"

        self.balance[from.clone()] = after

        let received = self.balance.get_or(to, 0) + amt
        self.balance[to.clone()] = received
        self.bump(from)
        self.bump(to)
        self.fees += fee
        if fee > 0: return "ok {after} {received} fee=5"

        return "ok {after} {received}"

    var fn do_freeze(id: String, value: Bool) String:
        if not self.balance.contains(id): return "error: unknown account {id}"

        self.frozen[id.clone()] = value
        return "ok"

    fn report() String:
        var lines = List[String]()
        var total = 0

        for id in self.balance.keys().sorted():
            let balance = self.balance.get_or(id, 0)

            let state = if self.frozen.get_or(id, false): "yes" else: "no"

            total += balance
            lines.append(
                "{id} balance={balance} limit={self.limit.get_or(id, 0)} ops={self.ops.get_or(id, 0)} rejected={self.rejected.get_or(id, 0)} frozen={state}"
            )

        lines.append("total balance={total} fees={self.fees}")
        return lines.join("\n")

    var fn exec(words: List[String]) String:
        let cmd = words[0]
        let n = words.length()
        if cmd == "open" and n == 3: return self.do_open(
            words[1].clone(), words[2].clone()
        )
        if cmd == "deposit" and n == 3: return self.do_deposit(
            words[1].clone(), words[2].clone()
        )
        if cmd == "withdraw" and n == 3: return self.do_withdraw(
            words[1].clone(), words[2].clone()
        )
        if cmd == "transfer" and n == 4: return self.do_transfer(
            words[1].clone(), words[2].clone(), words[3].clone()
        )
        if cmd == "freeze" and n == 2: return self.do_freeze(words[1].clone(), true)
        if cmd == "unfreeze" and n == 2: return self.do_freeze(words[1].clone(), false)
        if cmd == "report" and n == 1: return self.report()

        return "error: bad command"

export fn main() Int:
    var ledger = Ledger(
        balance: Map[String, Int](), limit: Map[String, Int](), ops: Map[String, Int](),
        rejected: Map[String, Int](), frozen: Map[String, Bool](), fees: 0
    )
    var out = ""

    for line in read_lines(stdin()).get():
        let words = tokens(line)
        if words.length() == 0: continue

        out += ledger.exec(words) + "\n"

    stdout().write(out).get()
    return 0
