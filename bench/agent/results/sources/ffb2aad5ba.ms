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

# Plain decimal digits only: `parse_int` also accepts a sign, which the spec rejects.
def digits(text: String) -> Optional[Int]:
    if text.is_empty() or text.starts_with("+") or text.starts_with("-"):
        return none

    return text.parse_int()

def amount_of(text: String) -> Optional[Int]:
    if let n = digits(text):
        if n > 0:
            return some(n)
    return none

# A debit takes the fee only when it moves a non-negative balance below zero.
def overdraft_fee(balance: Int, amount: Int) -> Int:
    if balance >= 0 and balance - amount < 0:
        return 5

    return 0

def fee_suffix(fee: Int) -> String:
    if fee > 0:
        return f" fee={fee}"

    return ""

impl Ledger:
    # Callers check existence first; this only supplies a value for the lookup.
    def account(id: String) -> Account:
        return self.accounts.get(
            id
        ).get(Account(balance: 0, limit: 0, ops: 0, rejected: 0, frozen: False))

    var def blame(id: String) -> Unit:
        var acc = self.account(id)
        acc.rejected += 1
        self.accounts.add(id, acc)

    var def open_account(id: String, limit: String) -> String:
        let cap = digits(limit)
        if cap.is_none():
            return "error: invalid limit"
        if self.accounts.contains(id):
            return f"error: account exists {id}"

        self.accounts.add(
            id,
            Account(
                balance: 0, limit: cap.get(0), ops: 0, rejected: 0, frozen: False
            )
        )
        return "ok"

    var def set_frozen(id: String, frozen: Bool) -> String:
        if not self.accounts.contains(id):
            return f"error: unknown account {id}"

        var acc = self.account(id)
        acc.frozen = frozen
        self.accounts.add(id, acc)
        return "ok"

    var def deposit(id: String, text: String) -> String:
        if not self.accounts.contains(id):
            return f"error: unknown account {id}"

        let amount = amount_of(text)

        if amount.is_none():
            self.blame(id.clone())
            return "error: invalid amount"

        var acc = self.account(id)

        if acc.frozen:
            self.blame(id.clone())
            return f"error: account frozen {id}"

        acc.balance += amount.get(0)
        acc.ops += 1
        self.accounts.add(id, acc)
        return f"ok {acc.balance}"

    var def withdraw(id: String, text: String) -> String:
        if not self.accounts.contains(id):
            return f"error: unknown account {id}"

        let amount = amount_of(text)

        if amount.is_none():
            self.blame(id.clone())
            return "error: invalid amount"

        var acc = self.account(id)

        if acc.frozen:
            self.blame(id.clone())
            return f"error: account frozen {id}"

        let fee = overdraft_fee(acc.balance, amount.get(0))
        let next = acc.balance - amount.get(0) - fee

        if next < -acc.limit:
            self.blame(id.clone())
            return f"error: overdraft limit exceeded {id}"

        acc.balance = next
        acc.ops += 1
        self.accounts.add(id, acc)
        self.fees += fee
        return f"ok {next}{fee_suffix(fee)}"

    var def transfer(from: String, to: String, text: String) -> String:
        if not self.accounts.contains(from):
            return f"error: unknown account {from}"
        if not self.accounts.contains(to):
            return f"error: unknown account {to}"

        if from == to:
            self.blame(from.clone())
            return "error: same account"

        let amount = amount_of(text)

        if amount.is_none():
            self.blame(from.clone())
            return "error: invalid amount"

        var src = self.account(from)

        if src.frozen:
            self.blame(from.clone())
            return f"error: account frozen {from}"

        var dst = self.account(to)

        if dst.frozen:
            self.blame(to.clone())
            return f"error: account frozen {to}"

        let fee = overdraft_fee(src.balance, amount.get(0))
        let next = src.balance - amount.get(0) - fee

        if next < -src.limit:
            self.blame(from.clone())
            return f"error: overdraft limit exceeded {from}"

        src.balance = next
        src.ops += 1
        dst.balance += amount.get(0)
        dst.ops += 1
        self.accounts.add(from, src)
        self.accounts.add(to, dst)
        self.fees += fee
        return f"ok {next} {dst.balance}{fee_suffix(fee)}"

    def report() -> String:
        var lines = List[String]()
        var total = 0

        for id in self.accounts.keys().sorted():
            let acc = self.account(id)
            total += acc.balance

            let frozen = "yes" if acc.frozen else "no"

            lines.append(
                f"{id} balance={acc.balance} limit={acc.limit} ops={acc.ops} rejected={acc.rejected} frozen={frozen}"
            )

        lines.append(f"total balance={total} fees={self.fees}")
        return lines.join("\n")

    var def run(tokens: List[String]) -> String:
        let cmd = tokens[0]
        let n = tokens.length()
        if cmd == "open" and n == 3:
            return self.open_account(tokens[1].clone(), tokens[2].clone())
        if cmd == "freeze" and n == 2:
            return self.set_frozen(tokens[1].clone(), True)
        if cmd == "unfreeze" and n == 2:
            return self.set_frozen(tokens[1].clone(), False)
        if cmd == "deposit" and n == 3:
            return self.deposit(tokens[1].clone(), tokens[2].clone())
        if cmd == "withdraw" and n == 3:
            return self.withdraw(tokens[1].clone(), tokens[2].clone())
        if cmd == "transfer" and n == 4:
            return self.transfer(
                tokens[1].clone(), tokens[2].clone(), tokens[3].clone()
            )

        return "error: bad command"

export def main() -> Int:
    var out = stdout()
    var ledger = Ledger(accounts: Map[String, Account](), fees: 0)

    for line in read_lines(stdin()).get():
        let tokens = line.replace("\t", " ").replace("\r", " ").split(" ").filter(
            lambda t: not t.is_empty()
        )
        if tokens.is_empty():
            continue

        if tokens.length() == 1 and tokens[0] == "report":
            out.write(f"{ledger.report()}\n").get()
        else:
            out.write(f"{ledger.run(tokens)}\n").get()

    return 0
