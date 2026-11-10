import (
    stdin from "@std/io/io.ms",
    lines from "@std/io/streams.ms",
)

type Ledger:
    balances: Map[String, Int]
    limits: Map[String, Int]
    ops: Map[String, Int]
    rejected: Map[String, Int]
    frozen: Map[String, Bool]
    ids: List[String]
    total_fees: Int

fn is_digits(s: String) Bool:
    if s.is_empty(): return false

    for c in s.chars():
        if not "0123456789".contains(c): return false
    return true

fn parse_num(s: String) Int:
    return s.parse_int().get(0)

fn valid_amount(s: String) Bool:
    return is_digits(s) and parse_num(s) > 0

// A debit of amt from balance b is charged the fee when it takes a
// non-negative balance below zero.
fn charged(b: Int, amt: Int) Bool:
    return b >= 0 and b - amt < 0

impl Ledger:
    fn bal(id: String) Int:
        return self.balances.get_or(id, 0)

    fn lim(id: String) Int:
        return self.limits.get_or(id, 0)

    fn is_frozen(id: String) Bool:
        return self.frozen.get_or(id, false)

    var fn count_op(id: String) Unit:
        n := self.ops.get_or(id.clone(), 0) + 1
        self.ops[id] = n

    var fn blame(id: String, msg: String) String:
        n := self.rejected.get_or(id.clone(), 0) + 1
        self.rejected[id] = n
        return msg

    var fn open_acct(id: String, limit_text: String) String:
        if not is_digits(limit_text): return "error: invalid limit"
        if self.balances.contains(id.clone()): return "error: account exists {id}"

        self.limits[id.clone()] = parse_num(limit_text)
        self.balances[id.clone()] = 0
        self.ops[id.clone()] = 0
        self.rejected[id.clone()] = 0
        self.frozen[id.clone()] = false
        self.ids.append(id)
        return "ok"

    var fn set_frozen(id: String, value: Bool) String:
        if not self.balances.contains(id.clone()): return "error: unknown account {id}"

        self.frozen[id] = value
        return "ok"

    var fn deposit(id: String, text: String) String:
        if not self.balances.contains(id.clone()): return "error: unknown account {id}"
        if not valid_amount(text.clone()):
            return self.blame(id.clone(), "error: invalid amount")
        if self.is_frozen(id.clone()):
            return self.blame(id.clone(), "error: account frozen {id}")

        amt := parse_num(text)
        nb := self.bal(id.clone()) + amt
        self.balances[id.clone()] = nb
        self.count_op(id)
        return "ok {nb}"

    var fn withdraw(id: String, text: String) String:
        if not self.balances.contains(id.clone()): return "error: unknown account {id}"
        if not valid_amount(text.clone()):
            return self.blame(id.clone(), "error: invalid amount")
        if self.is_frozen(id.clone()):
            return self.blame(id.clone(), "error: account frozen {id}")

        amt := parse_num(text)
        b := self.bal(id.clone())
        var nb = b - amt
        fee := charged(b, amt)
        if fee:
            nb -= 5
        if nb < -self.lim(id.clone()):
            return self.blame(id.clone(), "error: overdraft limit exceeded {id}")

        self.balances[id.clone()] = nb
        if fee:
            self.total_fees += 5
        self.count_op(id)
        if fee: return "ok {nb} fee=5"

        return "ok {nb}"

    var fn transfer(from: String, to: String, text: String) String:
        if not self.balances.contains(from.clone()):
            return "error: unknown account {from}"
        if not self.balances.contains(to.clone()): return "error: unknown account {to}"
        if from == to: return self.blame(from.clone(), "error: same account")
        if not valid_amount(text.clone()):
            return self.blame(from.clone(), "error: invalid amount")
        if self.is_frozen(from.clone()):
            return self.blame(from.clone(), "error: account frozen {from}")
        if self.is_frozen(to.clone()):
            return self.blame(to.clone(), "error: account frozen {to}")

        amt := parse_num(text)
        b := self.bal(from.clone())
        var nb = b - amt
        fee := charged(b, amt)
        if fee:
            nb -= 5
        if nb < -self.lim(from.clone()):
            return self.blame(from.clone(), "error: overdraft limit exceeded {from}")

        self.balances[from.clone()] = nb

        nt := self.bal(to.clone()) + amt
        self.balances[to.clone()] = nt
        if fee:
            self.total_fees += 5
        self.count_op(from)
        self.count_op(to)
        if fee: return "ok {nb} {nt} fee=5"

        return "ok {nb} {nt}"

    fn report() String:
        var rows = List[String]()
        var total = 0
        for id in self.ids:
            total += self.bal(id.clone())

        sorted_ids := self.ids.sorted()

        for id in sorted_ids:
            fz := if self.is_frozen(id.clone()): "yes" else: "no"
            rows.append(
                "{id} balance={self.bal(id.clone())} limit={self.lim(id.clone())} ops={self.ops.get_or(id.clone(), 0)} rejected={self.rejected.get_or(id.clone(), 0)} frozen={fz}"
            )

        rows.append("total balance={total} fees={self.total_fees}")
        return rows.join("\n")

    var fn run_cmd(t: List[String]) String:
        c := t[0].clone()
        n := t.length()
        if c == "open" and n == 3: return self.open_acct(t[1].clone(), t[2].clone())
        if c == "deposit" and n == 3: return self.deposit(t[1].clone(), t[2].clone())
        if c == "withdraw" and n == 3: return self.withdraw(t[1].clone(), t[2].clone())
        if c == "transfer" and n == 4:
            return self.transfer(t[1].clone(), t[2].clone(), t[3].clone())
        if c == "freeze" and n == 2: return self.set_frozen(t[1].clone(), true)
        if c == "unfreeze" and n == 2: return self.set_frozen(t[1].clone(), false)
        if c == "report" and n == 1: return self.report()

        return "error: bad command"

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn process() Unit!:
    var led = Ledger(
        balances: Map[String, Int](), limits: Map[String, Int](),
        ops: Map[String, Int](), rejected: Map[String, Int](),
        frozen: Map[String, Bool](), ids: List[String](), total_fees: 0
    )

    for raw in lines(stdin()):
        t := raw.replace("\t", " ").split(" ").filter(fn s: not s.is_empty())
        if t.is_empty(): continue

        print(led.run_cmd(t))


export fn main() Int:
    process().get()
    return 0
