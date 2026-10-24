from "@std/io.ms" import stdin, stdout
from "@std/streams.ms" import read_lines

type Account:
    limit: Int
    balance: Int = 0
    ops: Int = 0
    rejected: Int = 0
    frozen: Bool = False

type Ledger:
    accounts: Map[String, Account] = Map[String, Account]()
    fees: Int = 0

def parse_digits(text: String) -> Optional[Int]:
    if text.starts_with("+") or text.starts_with("-"): return none

    return text.parse_int()

def parse_amount(text: String) -> Optional[Int]:
    let value = parse_digits(text)
    if value.is_some() and value.get() > 0: return value

    return none

def fee_for(balance: Int, new_balance: Int) -> Int:
    if balance >= 0 and new_balance < 0: return 5

    return 0

def compare_ids(left: String, right: String) -> Int:
    if left < right: return -1
    if left == right: return 0

    return 1

def yes_no(flag: Bool) -> String:
    if flag: return "yes"

    return "no"

def suffix(fee: Int) -> String:
    if fee > 0: return f" fee={fee}"

    return ""

impl Ledger:
    var def blame(id: String) -> Unit:
        let acct = self.accounts.get(id).get()
        (
            self.accounts.add(
                id,
                Account(
                    limit: acct.limit, balance: acct.balance, ops: acct.ops,
                    rejected: acct.rejected + 1, frozen: acct.frozen
                )
            )
        )

    var def exec(words: List[String]) -> String:
        let cmd = words[0]
        let n = words.length()

        if cmd == "open":
            if n != 3: return "error: bad command"

            let limit = parse_digits(words[2])
            if limit.is_some() == False: return "error: invalid limit"

            let id = words[1]
            if self.accounts.contains(id): return f"error: account exists {id}"

            self.accounts.add(id, Account(limit: limit.get()))
            return "ok"

        if cmd == "freeze" or cmd == "unfreeze":
            if n != 2: return "error: bad command"

            let id = words[1]
            if self.accounts.contains(id) == False: return f"error: unknown account {id}"

            let acct = self.accounts.get(id).get()
            (
                self.accounts.add(
                    id,
                    Account(
                        limit: acct.limit, balance: acct.balance, ops: acct.ops,
                        rejected: acct.rejected, frozen: cmd == "freeze"
                    )
                )
            )
            return "ok"

        if cmd == "deposit":
            if n != 3: return "error: bad command"

            return self.deposit(words[1], words[2])

        if cmd == "withdraw":
            if n != 3: return "error: bad command"

            return self.withdraw(words[1], words[2])

        if cmd == "transfer":
            if n != 4: return "error: bad command"

            return self.transfer(words[1], words[2], words[3])

        return "error: bad command"

    var def deposit(id: String, text: String) -> String:
        if self.accounts.contains(id) == False: return f"error: unknown account {id}"

        let amount = parse_amount(text)

        if amount.is_some() == False:
            self.blame(id)
            return "error: invalid amount"

        let acct = self.accounts.get(id).get()

        if acct.frozen:
            self.blame(id)
            return f"error: account frozen {id}"

        let new_balance = acct.balance + amount.get()
        (
            self.accounts.add(
                id,
                Account(
                    limit: acct.limit, balance: new_balance, ops: acct.ops + 1,
                    rejected: acct.rejected, frozen: acct.frozen
                )
            )
        )
        return f"ok {new_balance}"

    var def withdraw(id: String, text: String) -> String:
        if self.accounts.contains(id) == False: return f"error: unknown account {id}"

        let amount = parse_amount(text)

        if amount.is_some() == False:
            self.blame(id)
            return "error: invalid amount"

        let acct = self.accounts.get(id).get()

        if acct.frozen:
            self.blame(id)
            return f"error: account frozen {id}"

        let fee = fee_for(acct.balance, acct.balance - amount.get())
        let new_balance = acct.balance - amount.get() - fee

        if new_balance < 0 - acct.limit:
            self.blame(id)
            return f"error: overdraft limit exceeded {id}"

        (
            self
            .accounts
            .add(
                id,
                Account(
                    limit: acct.limit, balance: new_balance, ops: acct.ops + 1,
                    rejected: acct.rejected, frozen: acct.frozen
                )
            )
        )
        self.fees += fee
        return f"ok {new_balance}{suffix(fee)}"

    var def transfer(from: String, to: String, text: String) -> String:
        if self.accounts.contains(from) == False: return f"error: unknown account {from}"
        if self.accounts.contains(to) == False: return f"error: unknown account {to}"

        if from == to:
            self.blame(from)
            return "error: same account"

        let amount = parse_amount(text)

        if amount.is_some() == False:
            self.blame(from)
            return "error: invalid amount"

        let src = self.accounts.get(from).get()

        if src.frozen:
            self.blame(from)
            return f"error: account frozen {from}"

        let dst = self.accounts.get(to).get()

        if dst.frozen:
            self.blame(to)
            return f"error: account frozen {to}"

        let fee = fee_for(src.balance, src.balance - amount.get())
        let new_src = src.balance - amount.get() - fee

        if new_src < 0 - src.limit:
            self.blame(from)
            return f"error: overdraft limit exceeded {from}"

        let new_dst = dst.balance + amount.get()
        (
            self.accounts.add(
                from,
                Account(
                    limit: src.limit, balance: new_src, ops: src.ops + 1,
                    rejected: src.rejected, frozen: src.frozen
                )
            )
        )
        (
            self.accounts.add(
                to,
                Account(
                    limit: dst.limit, balance: new_dst, ops: dst.ops + 1,
                    rejected: dst.rejected, frozen: dst.frozen
                )
            )
        )
        self.fees += fee
        return f"ok {new_src} {new_dst}{suffix(fee)}"

    def report() -> List[String]:
        let ids = self.accounts.keys().sorted(compare_ids)
        var lines: List[String] = []
        var total = 0

        for id in ids:
            let acct = self.accounts.get(id).get()
            total += acct.balance

            let frozen = yes_no(acct.frozen)
            lines.append(
                f"{id} balance={acct.balance} limit={acct.limit} ops={acct.ops} rejected={acct.rejected} frozen={frozen}"
            )

        lines.append(f"total balance={total} fees={self.fees}")
        return lines

export def main() -> Int:
    var ledger = Ledger()

    for line in read_lines(stdin()).get():
        let words = line.split("\t").join(" ").split(" ").filter(lambda w: w != "")
        if words.length() == 0: continue

        if words[0] == "report":
            if words.length() != 1:
                stdout().write("error: bad command\n").get()
                continue

            for out in ledger.report():
                stdout().write(f"{out}\n").get()
            continue

        stdout().write(f"{ledger.exec(words)}\n").get()

    return 0
