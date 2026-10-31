# Generator for c03-csv-group-sum. Deterministic; run: ms run bench/agent/gen.ms -- c03
import make_case, write_cases from "../../lib/gen.ms"
import GenCase from "../../lib/gen.ms"
import seeded from "../../lib/pyrandom.ms"

# The amount in cents, or none when `amt` is not digits with an optional fraction of one or two digits.
fn cents(amt: String) Int?:
    let parts = amt.split(".")
    if parts.length() > 2: return none

    let whole = parts[0].clone()
    if whole.is_empty() or not whole.chars().all(fn c: "0123456789".contains(c)): return none

    var fraction = ""

    if parts.length() == 2:
        fraction = parts[1].clone()
        if (
            fraction.length() < 1
            or fraction.length() > 2
            or not fraction.chars().all(fn c: "0123456789".contains(c))
        ): return none

    return whole.parse_int().get(0) * 100 + "{fraction}00".take(2).parse_int().get(0)

type Row:
    category: String
    cents: Int

fn parse_line(line: String) Row?:
    var cat = ""
    var amt = ""

    if line.starts_with("\""):
        let end = line.slice(1, line.length()).get("").index_of("\"").get(-1)
        if end < 0: return none

        let close = end + 1
        if line.slice(close + 1, close + 2).get("") != ",": return none

        cat = line.slice(1, close).get("")
        amt = line.slice(close + 2, line.length()).get("")
    else:
        let parts = line.split(",")
        if parts.length() != 2: return none

        cat = parts[0].clone()
        amt = parts[1].clone()

    if cat.contains("\"") or amt.contains(",") or cat.is_empty(): return none
    if let value = cents(amt): return Row(cat, value)

    return none

fn solve(s: String) String:
    var totals = Map[String, Int]()
    var order = List[String]()
    var bad = 0

    for raw in s.split("\n"):
        let line = if raw.ends_with("\r"): raw.slice(0, raw.length() - 1).get("") else: raw.clone()

        if line.trim().is_empty(): continue

        if let row = parse_line(line):
            if not totals.contains(row.category): order.append(row.category.clone())
            totals[row.category.clone()] = totals.get_or(row.category, 0) + row.cents
        else:
            bad += 1

    var out = ""

    for k in order.sorted():
        let v = totals.get(k).get(0)
        out = out + "{k}: {v / 100}.{"{v % 100}".pad_start(2, "0")}\n"

    if bad > 0: out = out + "skipped: {bad}\n"
    return out

fn mk(name: String, s: String) GenCase: make_case(name, s, solve(s))

export fn gen_c03() Unit:
    var rnd = seeded(3)
    let cats = ["food", "Rent", "a,b", "z", "x y", "café"]
    var lines = List[String]()

    for _n in 0..2000:
        let c = rnd.choice(cats)
        var a = ""

        if rnd.random() < 0.7:
            let whole = rnd.randint(0, 999)
            a = "{whole}.{"{rnd.randint(0, 99)}".pad_start(2, "0")}"
        else:
            a = "{rnd.randint(0, 50)}"

        lines.append((if c.contains(","): "\"{c}\"" else: c.clone()) + "," + a)

    let big = lines.join("\n") + "\n"
    let examples = [mk("basic", "fruit,1.50\n\"a,b\",2\nfruit,0.5\noops\nveg,x\n")]
    let hidden = examples.concat(
        [
            mk("empty", ""),
            mk("blank-lines", "\n\na,1\n\n"),
            mk("all-invalid", "x\ny,\n,3\na,b,c\n"),
            mk("float-trap", "a,0.1\na,0.2\na,0.7\n"),
            mk("big-sum", "a,99999999999.99\na,0.01\n"),
            mk("byte-order", "b,1\nB,1\na,1\n"),
            mk(
                "amount-forms", "a,1.\na,.5\na,1.234\na,-1\na,+1\na, 1\na,1\n"
            ),
            mk(
                "quoted-cat", "\"x,y,z\",1\n\"x,y,z\",2.25\n\"\",1\n\"a\"b\",1\n"
            ),
            mk("no-trailing-newline", "a,1\na,2"),
            mk("crlf", "a,1\r\nb,2\r\n"),
            mk("big", big),
            mk("unicode", "café,1\ncafe,2\n")
        ]
    )
    write_cases("c03-csv-group-sum", examples, hidden)
