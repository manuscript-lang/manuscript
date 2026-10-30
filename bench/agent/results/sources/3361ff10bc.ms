import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"

let FEE = 5

type Account:
    balance: Int
    limit: Int
    ops: Int
    rejected: Int
    frozen: Bool

type Ledger:
    accounts: Map[String, Account]
    fees: Int

# Parses a non-empty run of ASCII digits; anything else is none.
fn digits(text: String) Optional[Int]:
    for c in text.chars():
        if not "0123456789".contains(c):
            return none
    return text.parse_int()

# Returns the value of a digit-only text, or 0 when it is not a valid amount (0 is never a valid amount).
fn amount(text: String) Int:
    return digits(text).get(0)

fn tokenize(line: String) List[String]:
    return line.replace("\t", " ").split(" ").filter(fn t: t.byte_length() > 0)

fn emit(text: String) Unit:
    stdout().write(text + "\n").get()

fn unknown(id: String) String:
    return "error: unknown account " + id

fn empty_account() Account:
    return Account(balance: 0, limit: 0, ops: 0, rejected: 0, frozen: false)

# Records a rejection against the account that the error message names.
fn blame(var ledger: Ledger, id: String, message: String) String:
    if let acct = ledger.accounts.get(id):
        var copy = acct
        copy.rejected += 1
        ledger.accounts.add(id, copy)

    return message

fn is_frozen(ledger: Ledger, id: String) Bool:
    return ledger.accounts.get(id).get(empty_account()).frozen

# The overdraft fee applies when a debit takes a non-negative balance below zero.
fn fee_due(balance: Int, debit: Int) Int:
    if balance >= 0 and balance < debit:
        return FEE

    return 0

fn open_account(var ledger: Ledger, id: String, limit_text: String) String:
    let limit = digits(limit_text).get(-1)
    if limit < 0:
        return "error: invalid limit"
    if ledger.accounts.contains(id):
        return "error: account exists " + id

    ledger.accounts.add(
        id, Account(balance: 0, limit: limit, ops: 0, rejected: 0, frozen: false)
    )
    return "ok"

fn set_frozen(var ledger: Ledger, id: String, frozen: Bool) String:
    if let acct = ledger.accounts.get(id):
        var copy = acct
        copy.frozen = frozen
        ledger.accounts.add(id, copy)
        return "ok"

    return unknown(id)

fn deposit(var ledger: Ledger, id: String, text: String) String:
    if not ledger.accounts.contains(id):
        return unknown(id)

    let x = amount(text)
    if x <= 0:
        return blame(var ledger, id.clone(), "error: invalid amount")
    if is_frozen(ledger, id):
        return blame(var ledger, id.clone(), "error: account frozen " + id)

    var acct = ledger.accounts.get(id).get(empty_account())
    acct.balance += x
    acct.ops += 1
    ledger.accounts.add(id.clone(), acct.clone())
    return "ok " + acct.balance.to_string()

fn withdraw(var ledger: Ledger, id: String, text: String) String:
    if not ledger.accounts.contains(id):
        return unknown(id)

    let x = amount(text)
    if x <= 0:
        return blame(var ledger, id.clone(), "error: invalid amount")
    if is_frozen(ledger, id):
        return blame(var ledger, id.clone(), "error: account frozen " + id)

    var acct = ledger.accounts.get(id).get(empty_account())
    let fee = fee_due(acct.balance, x)
    let new = acct.balance - x - fee
    if new < -acct.limit:
        return blame(var ledger, id.clone(), "error: overdraft limit exceeded " + id)

    acct.balance = new
    acct.ops += 1
    ledger.accounts.add(id.clone(), acct.clone())
    ledger.fees += fee
    if fee > 0:
        return "ok " + new.to_string() + " fee=5"

    return "ok " + new.to_string()

fn transfer(var ledger: Ledger, from: String, to: String, text: String) String:
    if not ledger.accounts.contains(from):
        return unknown(from)
    if not ledger.accounts.contains(to):
        return unknown(to)
    if from == to:
        return blame(var ledger, from.clone(), "error: same account")

    let x = amount(text)
    if x <= 0:
        return blame(var ledger, from.clone(), "error: invalid amount")
    if is_frozen(ledger, from):
        return blame(var ledger, from.clone(), "error: account frozen " + from)
    if is_frozen(ledger, to):
        return blame(var ledger, to.clone(), "error: account frozen " + to)

    var src = ledger.accounts.get(from).get(empty_account())
    var dst = ledger.accounts.get(to).get(empty_account())
    let fee = fee_due(src.balance, x)
    let new = src.balance - x - fee
    if new < -src.limit:
        return blame(
            var ledger, from.clone(), "error: overdraft limit exceeded " + from
        )

    src.balance = new
    src.ops += 1
    dst.balance += x
    dst.ops += 1
    ledger.accounts.add(from.clone(), src.clone())
    ledger.accounts.add(to.clone(), dst.clone())
    ledger.fees += fee

    let line = "ok " + new.to_string() + " " + dst.balance.to_string()
    if fee > 0:
        return line + " fee=5"

    return line

fn handle(var ledger: Ledger, t: List[String]) String:
    let n = t.length()
    let cmd = t[0].clone()
    if cmd == "open" and n == 3:
        return open_account(var ledger, t[1].clone(), t[2].clone())
    if cmd == "deposit" and n == 3:
        return deposit(var ledger, t[1].clone(), t[2].clone())
    if cmd == "withdraw" and n == 3:
        return withdraw(var ledger, t[1].clone(), t[2].clone())
    if cmd == "transfer" and n == 4:
        return transfer(var ledger, t[1].clone(), t[2].clone(), t[3].clone())
    if cmd == "freeze" and n == 2:
        return set_frozen(var ledger, t[1].clone(), true)
    if cmd == "unfreeze" and n == 2:
        return set_frozen(var ledger, t[1].clone(), false)

    return "error: bad command"

fn report(ledger: Ledger) Unit:
    var total = 0

    for id in ledger.accounts.keys().sorted():
        let acct = ledger.accounts.get(id).get(empty_account())
        total += acct.balance

        var frozen = "no"
        if acct.frozen:
            frozen = "yes"
        emit(
            id
            + " balance="
            + acct.balance.to_string()
            + " limit="
            + acct.limit.to_string()
            + " ops="
            + acct.ops.to_string()
            + " rejected="
            + acct.rejected.to_string()
            + " frozen="
            + frozen
        )

    emit("total balance=" + total.to_string() + " fees=" + ledger.fees.to_string())

export fn main() Int:
    var ledger = Ledger(accounts: Map[String, Account](), fees: 0)

    if let lines = read_lines(stdin()):
        for line in lines:
            let t = tokenize(line)

            if t.length() == 1 and t[0] == "report":
                report(ledger)
            else if t.length() > 0:
                emit(handle(var ledger, t))

    return 0
