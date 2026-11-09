import stdin from "@std/io/io.ms"
import stdout from "@std/io/io.ms"
import lines from "@std/io/streams.ms"

// True when every character is an ASCII digit and there is at least one.
fn all_digits(s: String) Bool:
    if s.length() == 0:
        return false

    let ds = "0123456789".chars()
    for c in s.chars():
        if not ds.contains(c):
            return false
    return true

// Amount grammar: digits, optionally "." followed by one or two digits.
fn valid_amount(s: String) Bool:
    let parts = s.split(".")
    if parts.length() == 1:
        return all_digits(parts[0])

    if parts.length() == 2:
        let f = parts[1].length()
        return all_digits(parts[0]) and all_digits(parts[1]) and (f == 1 or f == 2)

    return false

// Splits a record into [category, amount]; an empty list means the line is invalid.
fn parse_line(line: String) List[String]:
    var cat = ""
    var amt = ""

    if line.starts_with("\""):
        let body = line.slice(1, line.length()).get()
        let parts = body.split("\"", 2)
        if parts.length() != 2:
            return List[String]()
        if not parts[1].starts_with(","):
            return List[String]()

        cat = parts[0].clone()
        amt = parts[1].slice(1, parts[1].length()).get()
    else:
        let parts = line.split(",")
        if parts.length() != 2:
            return List[String]()

        cat = parts[0].clone()
        amt = parts[1].clone()

    if cat.length() == 0 or not valid_amount(amt):
        return List[String]()

    return [cat, amt]

// Amount as a string of cents digits, e.g. "12.5" -> "1250".
fn to_cents(s: String) String:
    let parts = s.split(".")
    var frac = "00"

    if parts.length() == 2:
        frac = parts[1].clone()
        if frac.length() == 1:
            frac = "{frac}0"

    return "{parts[0]}{frac}"

// Exact decimal addition of two digit strings.
fn add_digits(a: String, b: String) String:
    let ds = "0123456789".chars()
    var i = a.length() - 1
    var j = b.length() - 1
    var carry = 0
    var out = List[String]()

    while i >= 0 or j >= 0 or carry > 0:
        var d = carry

        if i >= 0:
            d += index_of(ds, a.slice(i, i + 1).get())
            i -= 1

        if j >= 0:
            d += index_of(ds, b.slice(j, j + 1).get())
            j -= 1

        out.append("{d % 10}")
        carry = d / 10

    out.reverse()
    return out.join("")

fn index_of(ds: List[String], c: String) Int:
    for k in 0..10:
        if ds[k] == c:
            return k
    return 0

// Formats a cents digit string as "<int>.<two digits>".
fn format_total(cents: String) String:
    var s = cents
    while s.length() < 3:
        s = "0{s}"

    let whole = s.slice(0, s.length() - 2).get()
    let frac = s.slice(s.length() - 2, s.length()).get()

    // Strip leading zeros from the integer part, keeping one digit.
    var start = 0
    while start < whole.length() - 1 and whole.slice(start, start + 1).get() == "0":
        start += 1

    let w = whole.slice(start, whole.length()).get()
    return "{w}.{frac}"

// ms: allow_effect std.console.read
// ms: allow_effect std.console.write
fn run() Unit!:
    var totals = Map[String, String]()
    var skipped = 0

    for line in stdin() | lines:
        if line.trim().length() == 0:
            continue

        let rec = parse_line(line)

        if rec.length() == 0:
            skipped += 1
            continue

        let cat = rec[0]
        let cents = to_cents(rec[1])
        let prev = totals.get(cat).get("")
        let next = add_digits(prev, cents)
        totals[cat.clone()] = next

    var out = List[String]()
    var keys = totals.keys()
    keys.sort()

    for k in keys:
        let v = totals[k].clone()
        out.append("{k}: {format_total(v)}\n")

    if skipped > 0:
        out.append("skipped: {skipped}\n")
    stdout().write(out.join("")).get()
    return ok(unit)

export fn main() Int:
    run().get()
    return 0
