import (
    stdin, stdout from "@std/io/io.ms",
    lines, collect from "@std/io/streams.ms",
)

type Rec:
    cat: String
    amt: String

fn all_digits(s: String) Bool:
    for i in 0..s.length():
        if not "0123456789".contains(s.get(i)):
            return false
    return true

// Accepts digits, optionally followed by '.' and one or two digits.
fn valid_amount(s: String) Bool:
    let parts = s.split(".")
    if parts.length() == 1:
        return parts[0].length() > 0 and all_digits(parts[0])

    if parts.length() == 2:
        let ip = parts[0]
        let fp = parts[1]
        return (
            ip.length() > 0
            and all_digits(ip)
            and (fp.length() == 1 or fp.length() == 2)
            and all_digits(fp)
        )

    return false

fn parse_line(line: String) Rec?:
    var cat = ""
    var amt = ""

    if line.starts_with("\""):
        let rest = line.slice(1, line.length()).get()

        if let close = rest.find_char(fn(c: String) Bool: c == "\""):
            cat = rest.slice(0, close).get()

            let after = rest.slice(close + 1, rest.length()).get()
            if not after.starts_with(","):
                return none

            amt = after.slice(1, after.length()).get()
        else:
            return none
    else:
        let parts = line.split(",")
        if parts.length() != 2:
            return none

        cat = parts[0].clone()
        amt = parts[1].clone()

    if cat.length() == 0 or not valid_amount(amt):
        return none

    return Rec(cat: cat, amt: amt)

// Removes leading zeros but keeps at least one digit.
fn strip_zeros(s: String) String:
    var k = 0
    while k < s.length() - 1 and s.get(k) == "0":
        k += 1
    return s.slice(k, s.length()).get()

// Converts a valid amount to a digit string of hundredths.
fn to_cents(amt: String) String:
    let parts = amt.split(".")
    let ip = parts[0]
    if parts.length() == 1:
        return strip_zeros("{ip}00")

    let fp = parts[1]
    if fp.length() == 1:
        return strip_zeros("{ip}{fp}0")

    return strip_zeros("{ip}{fp}")

// Exact addition of two non-negative digit strings.
fn add_digits(a: String, b: String) String:
    var i = a.length() - 1
    var j = b.length() - 1
    var carry = 0
    var out = ""

    while i >= 0 or j >= 0 or carry > 0:
        var s = carry

        if i >= 0:
            s += a.get(i).parse_int().get(0)
            i -= 1

        if j >= 0:
            s += b.get(j).parse_int().get(0)
            j -= 1

        out = "{s % 10}{out}"
        carry = s / 10

    return strip_zeros(out)

export fn main() Int:
    let rows = collect(lines(stdin())).get()
    var totals = Map[String, String]()
    var cats = List[String]()
    var skipped = 0

    for row in rows:
        if row.trim().length() == 0:
            continue

        if let r = parse_line(row):
            let c = to_cents(r.amt)
            let key = r.cat.clone()
            let old = totals.get(key).get("").clone()

            if old.length() == 0:
                cats.append(key.clone())
                totals.add(key, c)
            else:
                let sum = add_digits(old, c)
                totals.add(key, sum)
        else:
            skipped += 1

    cats.sort()

    var out = stdout()

    for cat in cats:
        let t = totals.get(cat).get("0")
        let padded = t.pad_start(3, "0")
        let n = padded.length()
        let ip = padded.slice(0, n - 2).get()
        let fp = padded.slice(n - 2, n).get()
        out.write("{cat}: {ip}.{fp}\n").get()

    if skipped > 0:
        out.write("skipped: {skipped}\n").get()
    out.flush().get()
    return 0
