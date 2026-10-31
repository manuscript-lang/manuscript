# Generator for c36-bank-ledger. Deterministic; run: ms run bench/agent/gen.ms -- c36
import GenCase, make_case, write_cases from "../../lib/gen.ms"
import seeded from "../../lib/pyrandom.ms"
import Random from "../../lib/pyrandom.ms"
import words from "../../lib/text.ms"

let FEE = 5

fn digits(t: String) Bool: (
    not t.is_empty()
    and t.chars().all(fn c: "0123456789".contains(c))
)

fn arity(c: String) Int:
    if c == "open" or c == "deposit" or c == "withdraw": return 3
    if c == "transfer": return 4
    if c == "freeze" or c == "unfreeze": return 2
    if c == "report": return 1

    return 0

fn solve(s: String) String:
    var out = List[String]()
    var fees = 0
    var bal = Map[String, Int]()
    var lim = Map[String, Int]()
    var ops = Map[String, Int]()
    var rej = Map[String, Int]()
    var frozen = Set[String]()
    var names = List[String]()

    for line in s.split("\n"):
        let t = words(line)
        if t.is_empty(): continue

        let c = t[0].clone()

        if arity(c) == 0 or t.length() != arity(c):
            out.append("error: bad command")
            continue

        if c == "report":
            var tb = 0

            for k in names.sorted():
                let b = bal.get_or(k, 0)
                tb += b
                out.append(
                    "{k} balance={b} limit={lim.get_or(k, 0)} ops={ops.get_or(k, 0)} rejected={rej.get_or(k, 0)} frozen={if frozen.contains(k): "yes" else: "no"}"
                )

            out.append("total balance={tb} fees={fees}")
            continue

        if c == "open":
            if not digits(t[2]):
                out.append("error: invalid limit")
                continue

            if bal.contains(t[1]):
                out.append("error: account exists {t[1]}")
                continue

            names.append(t[1].clone())
            bal[t[1].clone()] = 0
            lim[t[1].clone()] = t[2].parse_int().get(0)
            ops[t[1].clone()] = 0
            rej[t[1].clone()] = 0
            out.append("ok")
            continue

        if c == "freeze" or c == "unfreeze":
            if not bal.contains(t[1]):
                out.append("error: unknown account {t[1]}")
                continue

            if c == "freeze":
                frozen.add(t[1].clone())
            else:
                frozen.remove(t[1].clone())

            out.append("ok")
            continue

        let ids = if c == "transfer": t.slice(1, 3).get([]) else: t.slice(1, 2).get([])

        let amount = t[t.length() - 1].clone()
        var unknown = ""
        for i in ids:
            if unknown == "" and not bal.contains(i): unknown = i.clone()

        if unknown != "":
            out.append("error: unknown account {unknown}")
            continue

        if c == "transfer" and ids[0] == ids[1]:
            rej[ids[0].clone()] = rej.get_or(ids[0], 0) + 1
            out.append("error: same account")
            continue

        if not (digits(amount) and amount.parse_int().get(0) > 0):
            rej[ids[0].clone()] = rej.get_or(ids[0], 0) + 1
            out.append("error: invalid amount")
            continue

        var fz = ""
        for i in ids:
            if fz == "" and frozen.contains(i): fz = i.clone()

        if fz != "":
            rej[fz.clone()] = rej.get_or(fz, 0) + 1
            out.append("error: account frozen {fz}")
            continue

        let n = amount.parse_int().get(0)
        var fee = 0
        let from = ids[0].clone()

        if c == "deposit":
            bal[from.clone()] = bal.get_or(from, 0) + n
            ops[from.clone()] = ops.get_or(from, 0) + 1
            out.append("ok {bal.get_or(from, 0)}")
            continue

        var new = bal.get_or(from, 0) - n

        if bal.get_or(from, 0) >= 0 and new < 0:
            new -= FEE
            fee = FEE

        if new < 0 - lim.get_or(from, 0):
            rej[from.clone()] = rej.get_or(from, 0) + 1
            out.append("error: overdraft limit exceeded {from}")
            continue

        bal[from.clone()] = new
        ops[from.clone()] = ops.get_or(from, 0) + 1
        fees += fee

        let sfx = if fee > 0: " fee={fee}" else: ""

        if c == "withdraw":
            out.append("ok {new}{sfx}")
        else:
            let to = ids[1].clone()
            bal[to.clone()] = bal.get_or(to, 0) + n
            ops[to.clone()] = ops.get_or(to, 0) + 1
            out.append("ok {new} {bal.get_or(to, 0)}{sfx}")

    return out.map(fn o: o + "\n").join("")

fn mk(name: String, s: String) GenCase: make_case(name, s, solve(s))

fn rand_script(var rnd: Random, n: Int, ids: List[String]) String:
    var lines = List[String]()

    for i in ids:
        let limit = ["0", "0", "10", "50", "200"][rnd.below(5)]
        lines.append("open {i} {limit}")

    for _k in 0..n:
        let r = rnd.random()
        let a = rnd.choice(ids)
        let b = rnd.choice(ids)
        var amt = ""

        if rnd.random() < 0.15:
            amt = rnd.choice(
                [
                    "1", "5", "7", "20", "40", "100", "250", "0", "x", "007", "-3",
                    "2.5"
                ]
            )
        else:
            let v = rnd.randint(1, 120)
            amt = "{["{v}"][rnd.below(1)]}"

        if r < 0.25:
            lines.append("deposit {a} {amt}")
        else if r < 0.5:
            lines.append("withdraw {a} {amt}")
        else if r < 0.8:
            lines.append("transfer {a} {b} {amt}")
        else if r < 0.82:
            lines.append("freeze {a}")
        else if r < 0.9:
            lines.append("unfreeze {a}")
        else if r < 0.92:
            lines.append("deposit zz {amt}")
        else if r < 0.95:
            lines.append("report")
        else:
            lines.append(rnd.choice(["bogus 1", "deposit a", "report now", "open q"]))

    lines.append("report")
    return lines.join("\n") + "\n"

export fn gen_c36() Unit:
    var rnd = seeded(36)
    let examples = [
        mk(
            "basic",
            "open a 20\nopen b 0\ndeposit a 10\nwithdraw a 25\nwithdraw a 10\ntransfer a b 3\nfreeze b\ndeposit b 1\nreport\n"
        )
    ]
    let small = rand_script(var rnd, 60, ["a", "b", "c"])
    var accounts = List[String]()
    for i in 0..12: accounts.append("acct{i}")

    let large = rand_script(var rnd, 1500, accounts)
    let hidden = examples.concat(
        [
            mk("empty-report", "report\n"),
            mk(
                "open-errors",
                "open a 5\nopen a 9\nopen b -1\nopen c\nopen d x\nopen e 0x1\nopen f 007\nreport\n"
            ),
            mk(
                "amount-forms",
                "open a 0\ndeposit a 007\ndeposit a 0\ndeposit a +5\ndeposit a 1.5\ndeposit a\ndeposit a  3\nwithdraw a -2\nreport\n"
            ),
            mk(
                "fee-once",
                "open a 100\nwithdraw a 10\nwithdraw a 10\ndeposit a 30\nwithdraw a 5\ndeposit a 5\nwithdraw a 1\nreport\n"
            ),
            mk(
                "fee-boundary",
                "open a 15\nwithdraw a 10\nwithdraw a 11\nwithdraw a 10\nopen b 0\nwithdraw b 1\ndeposit b 7\nwithdraw b 7\nwithdraw b 1\nreport\n"
            ),
            mk(
                "transfer-order",
                "open a 0\nopen b 0\nfreeze a\nfreeze b\ntransfer x y 1\ntransfer x a 1\ntransfer a y 1\ntransfer a a 1\ntransfer a a 0\ntransfer a b 0\ntransfer b a 1\ntransfer a b 1\nreport\n"
            ),
            mk(
                "transfer-fee",
                "open a 30\nopen b 0\ntransfer a b 10\ntransfer a b 10\ntransfer a b 10\ntransfer b a 2\nreport\n"
            ),
            mk(
                "frozen-lifecycle",
                "open a 10\ndeposit a 5\nfreeze a\nwithdraw a 1\ndeposit a 1\nunfreeze a\nunfreeze zz\nfreeze zz\nwithdraw a 1\nreport\n"
            ),
            mk(
                "whitespace-bad",
                "\n  open   a\t10  \n\n\tdeposit a 4\nOPEN b 1\nwithdraw a 1 2\nreport extra\n   report   \n"
            ),
            mk(
                "byte-order",
                "open b 0\nopen B 0\nopen a 0\nopen _ 0\nopen 10 0\nopen 9 0\nreport\n"
            ),
            mk("random-small", small),
            mk("random-large", large)
        ]
    )
    write_cases("c36-bank-ledger", examples, hidden)
