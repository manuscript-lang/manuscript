from "@std/io.ms" import stdin, stdout
from "@std/streams.ms" import read_lines

let OVERDRAFT_FEE = 5

type Account:
    balance: Int
    limit: Int
    ops: Int
    rejected: Int
    frozen: Bool

type Ledger:
    accounts: Map[String, Account]
    fees: Int

type Debit:
    ok: Bool
    balance: Int
    charged: Bool

def tokenize(line: String) -> List[String]:
    var tokens: List[String] = []
    var current = ""

    for c in line.chars():
        if c == " " or c == "\t":
            if current != "":
                tokens.append(current)
                current = ""
        else:
            current += c

    if current != "":
        tokens.append(current)
    return tokens

def parse_digits(text: String) -> Optional[Int]:
    if text == "":
        return none

    for c in text.chars():
        if c.compare("0") < 0 or c.compare("9") > 0:
            return none
    return text.parse_int()

def parse_amount(text: String) -> Optional[Int]:
    if let value = parse_digits(text):
        if value > 0:
            return some(value)
    return none

def yes_no(flag: Bool) -> String:
    if flag:
        return "yes"

    return "no"

def fee_suffix(charged: Bool) -> String:
    if charged:
        return f" fee={OVERDRAFT_FEE}"

    return ""

# Counts a failed command against `id` when that account exists, then returns the error text.
def reject(var ledger: Ledger, id: String, message: String) -> String:
    if let account = ledger.accounts.get(id):
        var updated = account
        updated.rejected += 1
        ledger.accounts.add(id, updated)

    return message

# Computes the balance after taking `amount` from `account`, charging the fee when it overdraws.
def debit(account: Account, amount: Int) -> Debit:
    var balance = account.balance - amount
    var charged = False

    if account.balance >= 0 and balance < 0:
        balance -= OVERDRAFT_FEE
        charged = True

    return Debit(ok: balance >= -account.limit, balance: balance, charged: charged)

def open_account(var ledger: Ledger, id: String, limit_text: String) -> String:
    if let limit = parse_digits(limit_text):
        if ledger.accounts.contains(id):
            return f"error: account exists {id}"

        (
            ledger
            .accounts
            .add(
                id,
                Account(
                    balance: 0, limit: limit, ops: 0, rejected: 0, frozen: False
                )
            )
        )
        return "ok"

    return "error: invalid limit"

def set_frozen(var ledger: Ledger, id: String, frozen: Bool) -> String:
    if let account = ledger.accounts.get(id):
        var updated = account
        updated.frozen = frozen
        ledger.accounts.add(id, updated)
        return "ok"

    return f"error: unknown account {id}"

def deposit(var ledger: Ledger, id: String, amount_text: String) -> String:
    if let account = ledger.accounts.get(id):
        if let amount = parse_amount(amount_text):
            if account.frozen:
                return reject(var ledger, id, f"error: account frozen {id}")

            var updated = account
            updated.balance += amount
            updated.ops += 1
            ledger.accounts.add(id, updated)
            return f"ok {updated.balance}"

        return reject(var ledger, id, "error: invalid amount")

    return f"error: unknown account {id}"

def withdraw(var ledger: Ledger, id: String, amount_text: String) -> String:
    if let account = ledger.accounts.get(id):
        if let amount = parse_amount(amount_text):
            if account.frozen:
                return reject(var ledger, id, f"error: account frozen {id}")

            let result = debit(account, amount)
            if not result.ok:
                return reject(var ledger, id, f"error: overdraft limit exceeded {id}")

            var updated = account
            updated.balance = result.balance
            updated.ops += 1
            ledger.accounts.add(id, updated)
            if result.charged:
                ledger.fees += OVERDRAFT_FEE
            return f"ok {result.balance}{fee_suffix(result.charged)}"

        return reject(var ledger, id, "error: invalid amount")

    return f"error: unknown account {id}"

def transfer(var ledger: Ledger, from_id: String, to_id: String, amount_text: String) -> String:
    if not ledger.accounts.contains(from_id):
        return f"error: unknown account {from_id}"
    if not ledger.accounts.contains(to_id):
        return f"error: unknown account {to_id}"
    if from_id == to_id:
        return reject(var ledger, from_id, "error: same account")

    if let amount = parse_amount(amount_text):
        let source = (
            ledger
            .accounts
            .get(from_id)
            .get(
                Account(
                    balance: 0, limit: 0, ops: 0, rejected: 0, frozen: False
                )
            )
        )
        let target = (
            ledger
            .accounts
            .get(to_id)
            .get(
                Account(
                    balance: 0, limit: 0, ops: 0, rejected: 0, frozen: False
                )
            )
        )
        if source.frozen:
            return reject(var ledger, from_id, f"error: account frozen {from_id}")
        if target.frozen:
            return reject(var ledger, to_id, f"error: account frozen {to_id}")

        let result = debit(source, amount)
        if not result.ok:
            return reject(
                var ledger, from_id, f"error: overdraft limit exceeded {from_id}"
            )

        var from_updated = source
        from_updated.balance = result.balance
        from_updated.ops += 1
        ledger.accounts.add(from_id, from_updated)

        var to_updated = target
        to_updated.balance += amount
        to_updated.ops += 1
        ledger.accounts.add(to_id, to_updated)
        if result.charged:
            ledger.fees += OVERDRAFT_FEE
        return f"ok {result.balance} {to_updated.balance}{fee_suffix(result.charged)}"

    return reject(var ledger, from_id, "error: invalid amount")

def report(var ledger: Ledger) -> List[String]:
    var lines: List[String] = []
    var total = 0
    let ids = (
        ledger
        .accounts
        .keys()
        .sorted(
            lambda (left: String, right: String) -> Int: left.compare(right)
        )
    )

    for id in ids:
        let account = (
            ledger
            .accounts
            .get(id)
            .get(
                Account(
                    balance: 0, limit: 0, ops: 0, rejected: 0, frozen: False
                )
            )
        )
        total += account.balance
        lines.append(
            f"{id} balance={account.balance} limit={account.limit} ops={account.ops} rejected={account.rejected} frozen={yes_no(account.frozen)}"
        )

    lines.append(f"total balance={total} fees={ledger.fees}")
    return lines

def handle(var ledger: Ledger, tokens: List[String]) -> List[String]:
    let command = tokens[0]
    let args = tokens.length() - 1
    if command == "open" and args == 2:
        return [open_account(var ledger, tokens[1], tokens[2])]
    if command == "deposit" and args == 2:
        return [deposit(var ledger, tokens[1], tokens[2])]
    if command == "withdraw" and args == 2:
        return [withdraw(var ledger, tokens[1], tokens[2])]
    if command == "transfer" and args == 3:
        return [transfer(var ledger, tokens[1], tokens[2], tokens[3])]
    if command == "freeze" and args == 1:
        return [set_frozen(var ledger, tokens[1], True)]
    if command == "unfreeze" and args == 1:
        return [set_frozen(var ledger, tokens[1], False)]
    if command == "report" and args == 0:
        return report(var ledger)

    return ["error: bad command"]

export def main() -> Int:
    var ledger = Ledger(accounts: Map[String, Account](), fees: 0)
    var out = stdout()

    for line in read_lines(stdin()).get():
        let tokens = tokenize(line)
        if tokens.length() > 0:
            for text in handle(var ledger, tokens):
                out.write(f"{text}\n").get()

    return 0
