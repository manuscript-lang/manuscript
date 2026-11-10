import (
    collect, lines from "@std/io/streams.ms",
    stdin, stdout from "@std/io/io.ms",
)

// A valid record: category text and amount in cents, as little-endian decimal digits.
type Rec:
    cat: String
    cents: List[Int]

// Digit k (little-endian) of a digit list, or 0 past its end.
fn digit_at(d: List[Int], k: Int) Int:
    if k < d.length():
        return d[k]

    return 0

// Exact sum of two little-endian digit lists.
fn add_digits(a: List[Int], b: List[Int]) List[Int]:
    var out = List[Int]()
    var carry = 0
    var k = 0

    while k < a.length() or k < b.length() or carry > 0:
        let s = carry + digit_at(a, k) + digit_at(b, k)
        out.append(s % 10)
        carry = s / 10
        k += 1

    return out

// Formats cents digits as "<whole>.<two digits>".
fn format_cents(d: List[Int]) String:
    var top = d.length() - 1
    if top < 2:
        top = 2
    while top > 2 and digit_at(d, top) == 0:
        top -= 1

    var s = ""
    var k = top

    while k >= 0:
        s = s + "{digit_at(d, k)}"
        if k == 2:
            s = s + "."
        k -= 1

    return s

// True when every scalar is an ASCII digit and there is at least one.
fn all_digits(s: String) Bool:
    let codes = s.scalar_values()
    if codes.length() == 0:
        return false

    for c in codes:
        if c < 48 or c > 57:
            return false
    return true

// Amount grammar: digits, optionally "." followed by one or two digits.
fn is_amount(s: String) Bool:
    let parts = s.split(".")
    if parts.length() == 1:
        return all_digits(parts[0])

    if parts.length() == 2:
        let frac = parts[1]
        let fl = frac.length()
        return all_digits(parts[0]) and fl >= 1 and fl <= 2 and all_digits(frac)

    return false

// Converts a valid amount such as "12.5" to little-endian cents digits.
fn cents_of(amt: String) List[Int]:
    let parts = amt.split(".")
    var text = parts[0].clone()

    if parts.length() == 2:
        text = text + (parts[1] + "00").slice_scalars(0, 2).get()
    else:
        text = text + "00"

    let codes = text.scalar_values()
    var out = List[Int]()
    var k = codes.length() - 1

    while k >= 0:
        out.append(codes[k] - 48)
        k -= 1

    return out

fn make_rec(cat: String, amt: String) Rec?:
    if cat.length() == 0 or not is_amount(amt):
        return none

    return Rec(cat: cat.clone(), cents: cents_of(amt))

// Parses one non-blank line; none when it is invalid.
fn parse_line(line: String) Rec?:
    if line.starts_with("\""):
        let parts = line.drop(1).split("\"", 2)
        if parts.length() != 2:
            return none

        let tail = parts[1]
        if not tail.starts_with(","):
            return none

        return make_rec(parts[0], tail.drop(1))

    let parts = line.split(",")
    if parts.length() != 2:
        return none

    return make_rec(parts[0], parts[1])

export fn main() Int:
    let all = collect(lines(stdin())).get()
    var recs = List[Rec]()
    var skipped = 0

    for line in all:
        if line.trim() == "":
            continue

        if let r = parse_line(line):
            recs.append(r)
        else:
            skipped += 1

    recs.sort(compare: fn(a: Rec, b: Rec) Int: a.cat.compare(b.cat))

    var i = 0

    while i < recs.length():
        var sum = List[Int]()
        var j = i

        while j < recs.length():
            if recs[j].cat != recs[i].cat:
                break

            sum = add_digits(sum, recs[j].cents)
            j += 1

        stdout().write("{recs[i].cat}: {format_cents(sum)}\n").get()
        i = j

    if skipped > 0:
        stdout().write("skipped: {skipped}\n").get()
    return 0
