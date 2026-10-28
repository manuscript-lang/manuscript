from "@std/io.ms" import stdin, stdout
from "@std/streams.ms" import read_lines

type Account:
    balance: Int
    limit: Int
    ops: Int
    rejected: Int
    frozen: Bool

type Ledger:
    accounts: Map[String, Account]
    fees: Int

let FEE = 5

def emit(line: String) -> Unit:
    stdout().write(f"{line}\n").get()

def words(line: String) -> List[String]:
    return line.split("\t").join(" ").split(" ").filter(lambda w: not w.is_empty())

# The value of an ASCII digit string, or -1 when the text is not one.
def parse_digits(text: String) -> Int:
    if text.is_empty(): return -1

    for v in text.scalar_values():
        if v < 48 or v > 57: return -1
    return text.parse_int().get(-1)

# A positive amount, or 0 when the text is not a valid amount.
def parse_amount(text: String) -> Int:
    let v = parse_digits(text)

    return v if v > 0 else 0

# Whether a debit of `amount` from `balance` overdraws it and so pays the fee.
def charges_fee(balance: Int, amount: Int) -> Bool:
    return balance >= 0 and balance - amount < 0

def blame(var ledger: Ledger, id: String) -> Unit:
    if var acc = ledger.accounts.get(id).clone():
        acc.rejected += 1
        ledger.accounts[id] = acc

def open_account(var ledger: Ledger, id: String, limit_text: String) -> String:
    let limit = parse_digits(limit_text)
    if limit < 0: return "error: invalid limit"
    if ledger.accounts.contains(id): return f"error: account exists {id}"

    ledger.accounts[id] = Account(
        balance: 0, limit: limit, ops: 0, rejected: 0, frozen: False
    )
    return "ok"

def set_frozen(var ledger: Ledger, id: String, frozen: Bool) -> String:
    if var acc = ledger.accounts.get(id).clone():
        acc.frozen = frozen
        ledger.accounts[id] = acc
        return "ok"

    return f"error: unknown account {id}"

def is_frozen(ledger: Ledger, id: String) -> Bool:
    return ledger.accounts[id].frozen

def deposit(var ledger: Ledger, id: String, amount_text: String) -> String:
    if not ledger.accounts.contains(id): return f"error: unknown account {id}"

    let amount = parse_amount(amount_text)

    if amount == 0:
        blame(var ledger, id.clone())
        return "error: invalid amount"

    if is_frozen(ledger, id):
        blame(var ledger, id.clone())
        return f"error: account frozen {id}"

    var acc = ledger.accounts[id].clone()
    acc.balance += amount
    acc.ops += 1
    ledger.accounts[id] = acc
    return f"ok {acc.balance}"

def withdraw(var ledger: Ledger, id: String, amount_text: String) -> String:
    if not ledger.accounts.contains(id): return f"error: unknown account {id}"

    let amount = parse_amount(amount_text)

    if amount == 0:
        blame(var ledger, id.clone())
        return "error: invalid amount"

    if is_frozen(ledger, id):
        blame(var ledger, id.clone())
        return f"error: account frozen {id}"

    var acc = ledger.accounts[id].clone()
    let fee = charges_fee(acc.balance, amount)
    let new = acc.balance - amount - (FEE if fee else 0)

    if new < -acc.limit:
        blame(var ledger, id.clone())
        return f"error: overdraft limit exceeded {id}"

    acc.balance = new
    acc.ops += 1
    ledger.accounts[id] = acc
    if fee: ledger.fees += FEE
    return f"ok {new}" + (" fee=5" if fee else "")

def transfer(var ledger: Ledger, from_id: String, to_id: String, amount_text: String) -> String:
    if not ledger.accounts.contains(from_id): return f"error: unknown account {from_id}"
    if not ledger.accounts.contains(to_id): return f"error: unknown account {to_id}"

    if from_id == to_id:
        blame(var ledger, from_id.clone())
        return "error: same account"

    let amount = parse_amount(amount_text)

    if amount == 0:
        blame(var ledger, from_id.clone())
        return "error: invalid amount"

    if is_frozen(ledger, from_id):
        blame(var ledger, from_id.clone())
        return f"error: account frozen {from_id}"

    if is_frozen(ledger, to_id):
        blame(var ledger, to_id.clone())
        return f"error: account frozen {to_id}"

    var src = ledger.accounts[from_id].clone()
    let fee = charges_fee(src.balance, amount)
    let new_from = src.balance - amount - (FEE if fee else 0)

    if new_from < -src.limit:
        blame(var ledger, from_id.clone())
        return f"error: overdraft limit exceeded {from_id}"

    var dst = ledger.accounts[to_id].clone()
    dst.balance += amount
    dst.ops += 1
    src.balance = new_from
    src.ops += 1
    ledger.accounts[from_id] = src
    ledger.accounts[to_id] = dst
    if fee: ledger.fees += FEE
    return f"ok {new_from} {dst.balance}" + (" fee=5" if fee else "")

def report(ledger: Ledger) -> Unit:
    var total = 0

    for id in ledger.accounts.keys().sorted():
        let acc = ledger.accounts[id].clone()
        total += acc.balance

        let frozen = "yes" if acc.frozen else "no"

        emit(
            f"{id} balance={acc.balance} limit={acc.limit} ops={acc.ops} rejected={acc.rejected} frozen={frozen}"
        )

    emit(f"total balance={total} fees={ledger.fees}")

def run(var ledger: Ledger, tokens: List[String]) -> String:
    let cmd = tokens[0]
    let n = tokens.length()
    if cmd == "open" and n == 3: return open_account(
        var ledger, tokens[1].clone(), tokens[2].clone()
    )
    if cmd == "freeze" and n == 2: return set_frozen(
        var ledger, tokens[1].clone(), True
    )
    if cmd == "unfreeze" and n == 2: return set_frozen(
        var ledger, tokens[1].clone(), False
    )
    if cmd == "deposit" and n == 3: return deposit(
        var ledger, tokens[1].clone(), tokens[2].clone()
    )
    if cmd == "withdraw" and n == 3: return withdraw(
        var ledger, tokens[1].clone(), tokens[2].clone()
    )
    if cmd == "transfer" and n == 4: return transfer(
        var ledger, tokens[1].clone(), tokens[2].clone(), tokens[3].clone()
    )

    return "error: bad command"

export def main() -> Int:
    var ledger = Ledger(accounts: Map[String, Account](), fees: 0)

    for line in read_lines(stdin()).get():
        let tokens = words(line)
        if tokens.is_empty(): continue

        if tokens[0] == "report" and tokens.length() == 1:
            report(ledger)
        else:
            emit(run(var ledger, tokens))

    return 0
