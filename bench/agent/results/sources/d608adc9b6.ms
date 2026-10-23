import {stdin, stdout} from "@std/io.ms"
import {read_lines} from "@std/streams.ms"

type Account:
    limit: Int
    balance: Int = 0
    ops: Int = 0
    rejected: Int = 0
    frozen: Bool = false

type Ledger:
    accounts: Map[String, Account] = Map[String, Account]()
    fees: Int = 0

fn parse_digits(text: String) Optional[Int]:
    if text.starts_with("+") or text.starts_with("-"): return none

    return text.parse_int()

fn parse_amount(text: String) Optional[Int]:
    let value = parse_digits(text)
    if value.is_some() and value.get() > 0: return value

    return none

fn fee_for(balance: Int, new_balance: Int) Int:
    if balance >= 0 and new_balance < 0: return 5

    return 0

fn compare_ids(left: String, right: String) Int:
    if left < right: return -1
    if left == right: return 0

    return 1

fn yes_no(flag: Bool) String:
    if flag: return "yes"

    return "no"

fn suffix(fee: Int) String:
    if fee > 0: return " fee={fee}"

    return ""

impl Ledger:
    var fn blame(id: String) Unit:
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

    var fn exec(words: List[String]) String:
        let cmd = words[0]
        let n = words.length()

        if cmd == "open":
            if n != 3: return "error: bad command"

            let limit = parse_digits(words[2])
            if limit.is_some() == false: return "error: invalid limit"

            let id = words[1]
            if self.accounts.contains(id): return "error: account exists {id}"

            self.accounts.add(id, Account(limit: limit.get()))
            return "ok"

        if cmd == "freeze" or cmd == "unfreeze":
            if n != 2: return "error: bad command"

            let id = words[1]
            if self.accounts.contains(id) == false: return "error: unknown account {id}"

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

    var fn deposit(id: String, text: String) String:
        if self.accounts.contains(id) == false: return "error: unknown account {id}"

        let amount = parse_amount(text)

        if amount.is_some() == false:
            self.blame(id)
            return "error: invalid amount"

        let acct = self.accounts.get(id).get()

        if acct.frozen:
            self.blame(id)
            return "error: account frozen {id}"

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
        return "ok {new_balance}"

    var fn withdraw(id: String, text: String) String:
        if self.accounts.contains(id) == false: return "error: unknown account {id}"

        let amount = parse_amount(text)

        if amount.is_some() == false:
            self.blame(id)
            return "error: invalid amount"

        let acct = self.accounts.get(id).get()

        if acct.frozen:
            self.blame(id)
            return "error: account frozen {id}"

        let fee = fee_for(acct.balance, acct.balance - amount.get())
        let new_balance = acct.balance - amount.get() - fee

        if new_balance < 0 - acct.limit:
            self.blame(id)
            return "error: overdraft limit exceeded {id}"

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
        return "ok {new_balance}{suffix(fee)}"

    var fn transfer(from: String, to: String, text: String) String:
        if self.accounts.contains(from) == false: return "error: unknown account {from}"
        if self.accounts.contains(to) == false: return "error: unknown account {to}"

        if from == to:
            self.blame(from)
            return "error: same account"

        let amount = parse_amount(text)

        if amount.is_some() == false:
            self.blame(from)
            return "error: invalid amount"

        let src = self.accounts.get(from).get()

        if src.frozen:
            self.blame(from)
            return "error: account frozen {from}"

        let dst = self.accounts.get(to).get()

        if dst.frozen:
            self.blame(to)
            return "error: account frozen {to}"

        let fee = fee_for(src.balance, src.balance - amount.get())
        let new_src = src.balance - amount.get() - fee

        if new_src < 0 - src.limit:
            self.blame(from)
            return "error: overdraft limit exceeded {from}"

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
        return "ok {new_src} {new_dst}{suffix(fee)}"

    fn report() List[String]:
        let ids = self.accounts.keys().sorted(compare_ids)
        var lines: List[String] = []
        var total = 0

        for id in ids:
            let acct = self.accounts.get(id).get()
            total += acct.balance

            let frozen = yes_no(acct.frozen)
            lines.append(
                "{id} balance={acct.balance} limit={acct.limit} ops={acct.ops} rejected={acct.rejected} frozen={frozen}"
            )

        lines.append("total balance={total} fees={self.fees}")
        return lines

export fn main() Int:
    var ledger = Ledger()

    for line in read_lines(stdin()).get():
        let words = line.split("\t").join(" ").split(" ").filter(fn(w): w != "")
        if words.length() == 0: continue

        if words[0] == "report":
            if words.length() != 1:
                stdout().write("error: bad command\n").get()
                continue

            for out in ledger.report():
                stdout().write("{out}\n").get()
            continue

        stdout().write("{ledger.exec(words)}\n").get()

    return 0
