import stdout from "@std/io/io.ms"
import stdin from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

type Ledger:
    balance: Map[String, Int]
    limit: Map[String, Int]
    ops: Map[String, Int]
    rejected: Map[String, Int]
    frozen: Map[String, Bool]
    ids: List[String]
    fees: Int

// True when text is non-empty and made only of ASCII digits.
fn is_digits(s: String) Bool:
    if s.length() == 0:
        return false
    for v in s.scalar_values():
        if v < 48 or v > 57:
            return false
    return true

// Value of a digit-only string (leading zeros allowed); 0 when it is all zeros.
fn digits_value(s: String) Int:
    let t = s.trim_start_chars("0")
    if t.length() == 0:
        return 0
    return t.parse_int().get(0)

fn valid_limit(s: String) Bool:
    return is_digits(s)

fn valid_amount(s: String) Bool:
    if not is_digits(s):
        return false
    return digits_value(s) > 0

fn blame(var l: Ledger, id: String) Unit:
    l.rejected[id.clone()] = l.rejected.get_or(id, 0) + 1

// Computes the withdrawal result for account `id` taking `amount`.
// Returns the new balance and whether a fee applies; the caller checks the limit.
fn debit_preview(l: Ledger, id: String, amount: Int) Int:
    let bal = l.balance.get_or(id, 0)
    let new_bal = bal - amount
    if bal >= 0 and new_bal < 0:
        return new_bal - 5
    return new_bal

fn fee_applies(l: Ledger, id: String, amount: Int) Bool:
    let bal = l.balance.get_or(id, 0)
    return bal >= 0 and bal - amount < 0

fn report(l: Ledger) String:
    var out = ""
    var total = 0
    for id in l.ids.sorted():
        let bal = l.balance.get_or(id, 0)
        total += bal
        let frozen_text = if l.frozen.get_or(id, false): "yes" else: "no"
        out += "{id} balance={bal} limit={l.limit.get_or(id, 0)} ops={l.ops.get_or(id, 0)} rejected={l.rejected.get_or(id, 0)} frozen={frozen_text}\n"
    out += "total balance={total} fees={l.fees}"
    return out

fn cmd_open(var l: Ledger, toks: List[String]) String:
    let id = toks[1].clone()
    let lim = toks[2].clone()
    if not valid_limit(lim):
        return "error: invalid limit"
    if l.balance.contains(id):
        return "error: account exists {id}"
    l.balance[id.clone()] = 0
    l.limit[id.clone()] = digits_value(lim)
    l.ops[id.clone()] = 0
    l.rejected[id.clone()] = 0
    l.frozen[id.clone()] = false
    l.ids.append(id.clone())
    return "ok"

fn cmd_freeze(var l: Ledger, toks: List[String], flag: Bool) String:
    let id = toks[1].clone()
    if not l.balance.contains(id):
        return "error: unknown account {id}"
    l.frozen[id.clone()] = flag
    return "ok"

fn cmd_deposit(var l: Ledger, toks: List[String]) String:
    let id = toks[1].clone()
    let amt_text = toks[2].clone()
    if not l.balance.contains(id):
        return "error: unknown account {id}"
    if not valid_amount(amt_text):
        blame(var l, id.clone())
        return "error: invalid amount"
    if l.frozen.get_or(id, false):
        blame(var l, id.clone())
        return "error: account frozen {id}"
    let amt = digits_value(amt_text)
    l.balance[id.clone()] = l.balance.get_or(id, 0) + amt
    l.ops[id.clone()] = l.ops.get_or(id, 0) + 1
    return "ok {l.balance.get_or(id, 0)}"

fn cmd_withdraw(var l: Ledger, toks: List[String]) String:
    let id = toks[1].clone()
    let amt_text = toks[2].clone()
    if not l.balance.contains(id):
        return "error: unknown account {id}"
    if not valid_amount(amt_text):
        blame(var l, id.clone())
        return "error: invalid amount"
    if l.frozen.get_or(id, false):
        blame(var l, id.clone())
        return "error: account frozen {id}"
    let amt = digits_value(amt_text)
    let new_bal = debit_preview(l, id, amt)
    if new_bal < -l.limit.get_or(id, 0):
        blame(var l, id.clone())
        return "error: overdraft limit exceeded {id}"
    let fee = fee_applies(l, id, amt)
    l.balance[id.clone()] = new_bal
    if fee:
        l.fees += 5
    l.ops[id.clone()] = l.ops.get_or(id, 0) + 1
    if fee:
        return "ok {new_bal} fee=5"
    return "ok {new_bal}"

fn cmd_transfer(var l: Ledger, toks: List[String]) String:
    let from = toks[1].clone()
    let to = toks[2].clone()
    let amt_text = toks[3].clone()
    if not l.balance.contains(from):
        return "error: unknown account {from}"
    if not l.balance.contains(to):
        return "error: unknown account {to}"
    if from == to:
        blame(var l, from.clone())
        return "error: same account"
    if not valid_amount(amt_text):
        blame(var l, from.clone())
        return "error: invalid amount"
    if l.frozen.get_or(from, false):
        blame(var l, from.clone())
        return "error: account frozen {from}"
    if l.frozen.get_or(to, false):
        blame(var l, to.clone())
        return "error: account frozen {to}"
    let amt = digits_value(amt_text)
    let new_from = debit_preview(l, from, amt)
    if new_from < -l.limit.get_or(from, 0):
        blame(var l, from.clone())
        return "error: overdraft limit exceeded {from}"
    let fee = fee_applies(l, from, amt)
    l.balance[from.clone()] = new_from
    l.balance[to.clone()] = l.balance.get_or(to, 0) + amt
    if fee:
        l.fees += 5
    l.ops[from.clone()] = l.ops.get_or(from, 0) + 1
    l.ops[to.clone()] = l.ops.get_or(to, 0) + 1
    if fee:
        return "ok {new_from} {l.balance.get_or(to, 0)} fee=5"
    return "ok {new_from} {l.balance.get_or(to, 0)}"

fn process(var l: Ledger, toks: List[String]) String:
    let cmd = toks[0]
    let n = toks.length()
    if cmd == "open" and n == 3:
        return cmd_open(var l, toks)
    if (cmd == "freeze" or cmd == "unfreeze") and n == 2:
        return cmd_freeze(var l, toks, cmd == "freeze")
    if cmd == "deposit" and n == 3:
        return cmd_deposit(var l, toks)
    if cmd == "withdraw" and n == 3:
        return cmd_withdraw(var l, toks)
    if cmd == "transfer" and n == 4:
        return cmd_transfer(var l, toks)
    if cmd == "report" and n == 1:
        return report(l)
    return "error: bad command"

fn run() Unit!:
    var led = Ledger(balance: Map[String, Int](), limit: Map[String, Int](), ops: Map[String, Int](), rejected: Map[String, Int](), frozen: Map[String, Bool](), ids: List[String](), fees: 0)
    for line in lines(stdin()):
        let toks = line.fields()
        if toks.length() == 0:
            continue
        let out = process(var led, toks)
        try stdout().write(out + "\n")
    return ok(unit)

export fn main() Int:
    run().get()
    return 0
