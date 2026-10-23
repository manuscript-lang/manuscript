import stdin from "@std/io.ms"
import stdout from "@std/io.ms"
import read_all from "@std/io.ms"

# One ledger account. Records are copied on assignment, so changes are written back with `add`.
type Account:
    limit: Int
    balance: Int
    ops: Int
    rejected: Int
    frozen: Bool

type Ledger:
    accounts: Map[String, Account]
    fees: Int

# Returns true when every scalar of `text` is an ASCII digit and there is at least one.
fn is_digits(text: String) Bool:
    if text.is_empty():
        return false

    for value in text.scalar_values():
        if value < 48 or value > 57:
            return false
    return true

# Returns true for a digit string whose value is greater than zero.
fn is_positive(text: String) Bool:
    return is_digits(text) and text.parse_int().get(0) > 0

# Splits a line into tokens separated by runs of spaces or tabs.
fn split_tokens(line: String) List[String]:
    var tokens: List[String] = []
    var current = ""

    for c in line.chars():
        if c == " " or c == "\t":
            if not current.is_empty():
                tokens.append(current)
            current = ""
        else:
            current = current.concat(c)

    if not current.is_empty():
        tokens.append(current)
    return tokens

fn yes_no(flag: Bool) String:
    if flag:
        return "yes"

    return "no"

# Overdraft fee charged when a debit takes a non-negative balance below zero.
fn fee_for(balance: Int, amount: Int) Int:
    if balance >= 0 and balance - amount < 0:
        return 5

    return 0

impl Ledger:
    # Records one rejected command against the account named in its error.
    var fn blame(id: String) Unit:
        var acct = self.accounts.get(id).get()

        acct.rejected += 1
        self.accounts.add(id, acct)

    var fn open_account(id: String, limit_text: String) String:
        if not is_digits(limit_text):
            return "error: invalid limit"
        if self.accounts.contains(id):
            return "error: account exists {id}"

        (
            self
            .accounts
            .add(
                id,
                Account(
                    limit: limit_text.parse_int().get(0), balance: 0, ops: 0,
                    rejected: 0, frozen: false
                )
            )
        )
        return "ok"

    var fn set_frozen(id: String, frozen: Bool) String:
        if not self.accounts.contains(id):
            return "error: unknown account {id}"

        var acct = self.accounts.get(id).get()

        acct.frozen = frozen
        self.accounts.add(id, acct)
        return "ok"

    var fn deposit(id: String, amount_text: String) String:
        if not self.accounts.contains(id):
            return "error: unknown account {id}"

        if not is_positive(amount_text):
            self.blame(id)
            return "error: invalid amount"

        var acct = self.accounts.get(id).get()

        if acct.frozen:
            self.blame(id)
            return "error: account frozen {id}"

        acct.balance += amount_text.parse_int().get(0)
        acct.ops += 1
        self.accounts.add(id, acct)
        return "ok {acct.balance}"

    var fn withdraw(id: String, amount_text: String) String:
        if not self.accounts.contains(id):
            return "error: unknown account {id}"

        if not is_positive(amount_text):
            self.blame(id)
            return "error: invalid amount"

        var acct = self.accounts.get(id).get()

        if acct.frozen:
            self.blame(id)
            return "error: account frozen {id}"

        let amount = amount_text.parse_int().get(0)
        let fee = fee_for(acct.balance, amount)
        let new_balance = acct.balance - amount - fee

        if new_balance < -acct.limit:
            self.blame(id)
            return "error: overdraft limit exceeded {id}"

        acct.balance = new_balance
        acct.ops += 1
        self.accounts.add(id, acct)
        self.fees += fee
        if fee > 0:
            return "ok {new_balance} fee={fee}"

        return "ok {new_balance}"

    var fn transfer(from: String, to: String, amount_text: String) String:
        if not self.accounts.contains(from):
            return "error: unknown account {from}"
        if not self.accounts.contains(to):
            return "error: unknown account {to}"

        if from == to:
            self.blame(from)
            return "error: same account"

        if not is_positive(amount_text):
            self.blame(from)
            return "error: invalid amount"

        var src = self.accounts.get(from).get()
        var dst = self.accounts.get(to).get()

        if src.frozen:
            self.blame(from)
            return "error: account frozen {from}"

        if dst.frozen:
            self.blame(to)
            return "error: account frozen {to}"

        let amount = amount_text.parse_int().get(0)
        let fee = fee_for(src.balance, amount)
        let new_balance = src.balance - amount - fee

        if new_balance < -src.limit:
            self.blame(from)
            return "error: overdraft limit exceeded {from}"

        src.balance = new_balance
        src.ops += 1
        dst.balance += amount
        dst.ops += 1
        self.accounts.add(from, src)
        self.accounts.add(to, dst)
        self.fees += fee
        if fee > 0:
            return "ok {src.balance} {dst.balance} fee={fee}"

        return "ok {src.balance} {dst.balance}"

    fn report() String:
        var lines: List[String] = []
        var total = 0

        for id in self.accounts.keys().sorted(by_compare):
            let acct = self.accounts.get(id).get()

            total += acct.balance
            lines.append(
                "{id} balance={acct.balance} limit={acct.limit} ops={acct.ops} rejected={acct.rejected} frozen={yes_no(acct.frozen)}"
            )

        lines.append("total balance={total} fees={self.fees}")
        return lines.join("\n")

fn by_compare(left: String, right: String) Int:
    return left.compare(right)

# Runs one tokenized command and returns the text of its output.
fn execute(var ledger: Ledger, tokens: List[String]) String:
    let command = tokens.get(0)
    let count = tokens.length()
    if command == "open" and count == 3:
        return ledger.open_account(tokens.get(1), tokens.get(2))
    if command == "deposit" and count == 3:
        return ledger.deposit(tokens.get(1), tokens.get(2))
    if command == "withdraw" and count == 3:
        return ledger.withdraw(tokens.get(1), tokens.get(2))
    if command == "transfer" and count == 4:
        return ledger.transfer(tokens.get(1), tokens.get(2), tokens.get(3))
    if command == "freeze" and count == 2:
        return ledger.set_frozen(tokens.get(1), true)
    if command == "unfreeze" and count == 2:
        return ledger.set_frozen(tokens.get(1), false)
    if command == "report" and count == 1:
        return ledger.report()

    return "error: bad command"

export fn main() Int:
    let text = read_all(stdin()).get().decode_utf8().get("")
    var ledger = Ledger(accounts: Map[String, Account](), fees: 0)

    for line in text.split("\n"):
        let tokens = split_tokens(line)

        if not tokens.is_empty():
            stdout().write("{execute(var ledger, tokens)}\n").get()

    stdout().flush().get()
    return 0
