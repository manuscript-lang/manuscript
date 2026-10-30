import stdin, stdout from "@std/io.ms"
import read_lines from "@std/streams.ms"

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
fn digits(text: String) Optional[Int]:
    if text.is_empty() or text.starts_with("+") or text.starts_with("-"):
        return none

    return text.parse_int()

fn amount_of(text: String) Optional[Int]:
    if let n = digits(text):
        if n > 0:
            return some(n)
    return none

# A debit takes the fee only when it moves a non-negative balance below zero.
fn overdraft_fee(balance: Int, amount: Int) Int:
    if balance >= 0 and balance - amount < 0:
        return 5

    return 0

fn fee_suffix(fee: Int) String:
    if fee > 0:
        return " fee={fee}"

    return ""

impl Ledger:
    # Callers check existence first; this only supplies a value for the lookup.
    fn account(id: String) Account:
        return self.accounts.get(
            id
        ).get(Account(balance: 0, limit: 0, ops: 0, rejected: 0, frozen: false))

    var fn blame(id: String) Unit:
        var acc = self.account(id)
        acc.rejected += 1
        self.accounts.add(id, acc)

    var fn open_account(id: String, limit: String) String:
        let cap = digits(limit)
        if cap.is_none():
            return "error: invalid limit"
        if self.accounts.contains(id):
            return "error: account exists {id}"

        self.accounts.add(
            id,
            Account(
                balance: 0, limit: cap.get(0), ops: 0, rejected: 0, frozen: false
            )
        )
        return "ok"

    var fn set_frozen(id: String, frozen: Bool) String:
        if not self.accounts.contains(id):
            return "error: unknown account {id}"

        var acc = self.account(id)
        acc.frozen = frozen
        self.accounts.add(id, acc)
        return "ok"

    var fn deposit(id: String, text: String) String:
        if not self.accounts.contains(id):
            return "error: unknown account {id}"

        let amount = amount_of(text)

        if amount.is_none():
            self.blame(id.clone())
            return "error: invalid amount"

        var acc = self.account(id)

        if acc.frozen:
            self.blame(id.clone())
            return "error: account frozen {id}"

        acc.balance += amount.get(0)
        acc.ops += 1
        self.accounts.add(id, acc)
        return "ok {acc.balance}"

    var fn withdraw(id: String, text: String) String:
        if not self.accounts.contains(id):
            return "error: unknown account {id}"

        let amount = amount_of(text)

        if amount.is_none():
            self.blame(id.clone())
            return "error: invalid amount"

        var acc = self.account(id)

        if acc.frozen:
            self.blame(id.clone())
            return "error: account frozen {id}"

        let fee = overdraft_fee(acc.balance, amount.get(0))
        let next = acc.balance - amount.get(0) - fee

        if next < -acc.limit:
            self.blame(id.clone())
            return "error: overdraft limit exceeded {id}"

        acc.balance = next
        acc.ops += 1
        self.accounts.add(id, acc)
        self.fees += fee
        return "ok {next}{fee_suffix(fee)}"

    var fn transfer(from: String, to: String, text: String) String:
        if not self.accounts.contains(from):
            return "error: unknown account {from}"
        if not self.accounts.contains(to):
            return "error: unknown account {to}"

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
            return "error: account frozen {from}"

        var dst = self.account(to)

        if dst.frozen:
            self.blame(to.clone())
            return "error: account frozen {to}"

        let fee = overdraft_fee(src.balance, amount.get(0))
        let next = src.balance - amount.get(0) - fee

        if next < -src.limit:
            self.blame(from.clone())
            return "error: overdraft limit exceeded {from}"

        src.balance = next
        src.ops += 1
        dst.balance += amount.get(0)
        dst.ops += 1
        self.accounts.add(from, src)
        self.accounts.add(to, dst)
        self.fees += fee
        return "ok {next} {dst.balance}{fee_suffix(fee)}"

    fn report() String:
        var lines = List[String]()
        var total = 0

        for id in self.accounts.keys().sorted():
            let acc = self.account(id)
            total += acc.balance

            let frozen = if acc.frozen: "yes" else: "no"

            lines.append(
                "{id} balance={acc.balance} limit={acc.limit} ops={acc.ops} rejected={acc.rejected} frozen={frozen}"
            )

        lines.append("total balance={total} fees={self.fees}")
        return lines.join("\n")

    var fn run(tokens: List[String]) String:
        let cmd = tokens[0]
        let n = tokens.length()
        if cmd == "open" and n == 3:
            return self.open_account(tokens[1].clone(), tokens[2].clone())
        if cmd == "freeze" and n == 2:
            return self.set_frozen(tokens[1].clone(), true)
        if cmd == "unfreeze" and n == 2:
            return self.set_frozen(tokens[1].clone(), false)
        if cmd == "deposit" and n == 3:
            return self.deposit(tokens[1].clone(), tokens[2].clone())
        if cmd == "withdraw" and n == 3:
            return self.withdraw(tokens[1].clone(), tokens[2].clone())
        if cmd == "transfer" and n == 4:
            return self.transfer(
                tokens[1].clone(), tokens[2].clone(), tokens[3].clone()
            )

        return "error: bad command"

export fn main() Int:
    var out = stdout()
    var ledger = Ledger(accounts: Map[String, Account](), fees: 0)

    for line in read_lines(stdin()).get():
        let tokens = line.replace("\t", " ").replace("\r", " ").split(" ").filter(
            fn t: not t.is_empty()
        )
        if tokens.is_empty():
            continue

        if tokens.length() == 1 and tokens[0] == "report":
            out.write("{ledger.report()}\n").get()
        else:
            out.write("{ledger.run(tokens)}\n").get()

    return 0
