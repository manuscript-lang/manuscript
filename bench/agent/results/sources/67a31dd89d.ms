import (
    stdin, stdout from "@std/io/io.ms",
    read_all from "@std/io/streams.ms",
)

// A parsed input line. `ok` is false when the line is invalid.
type Record:
    ok: Bool
    category: String
    amount: String  // digits of the amount in cents, no sign, no leading zero rules

fn bad() Record:
    return Record(ok: false, category: "", amount: "")

fn is_digit(c: String) Bool:
    return c.length() == 1 and c.compare("0") >= 0 and c.compare("9") <= 0

fn digit_value(c: String) Int:
    return c.parse_int().get(0)

// Returns the amount as a string of cents digits ("12.5" -> "1250"), or "" when invalid.
fn amount_cents(s: String) String:
    let n = s.length()
    if n == 0:
        return ""

    var int_len = 0
    while int_len < n and s.get(int_len) != ".":
        int_len += 1
    if int_len == 0:
        return ""

    var k = 0

    while k < int_len:
        if not is_digit(s.get(k)):
            return ""

        k += 1

    if int_len == n:
        return "{s}00"

    // there is a dot at int_len
    let frac = s.slice(int_len + 1, n).get()
    let fl = frac.length()
    if fl == 0 or fl > 2:
        return ""

    var m = 0

    while m < fl:
        if not is_digit(frac.get(m)):
            return ""

        m += 1

    var padded = "{frac}"
    if fl == 1:
        padded = "{frac}0"
    return "{s.slice(0, int_len).get()}{padded}"

// Parses one non-blank line into a record.
fn parse_line(line: String) Record:
    let n = line.length()
    if n == 0:
        return bad()

    var category = ""
    var amount = ""

    if line.get(0) == "\"":
        var i = 1
        while i < n and line.get(i) != "\"":
            i += 1
        if i >= n:
            return bad()

        // closing quote at i; must be followed by a comma
        if i + 1 >= n or line.get(i + 1) != ",":
            return bad()

        category = line.slice(1, i).get()
        amount = line.slice(i + 2, n).get()
    else:
        var j = 0
        while j < n and line.get(j) != ",":
            j += 1
        if j >= n:
            return bad()

        category = line.slice(0, j).get()
        amount = line.slice(j + 1, n).get()

    if category.length() == 0:
        return bad()

    let cents = amount_cents(amount)
    if cents.length() == 0:
        return bad()

    return Record(ok: true, category: category, amount: cents)

// Adds two non-negative decimal digit strings exactly.
fn add_digits(a: String, b: String) String:
    var i = a.length() - 1
    var j = b.length() - 1
    var carry = 0
    var out = ""

    while i >= 0 or j >= 0 or carry > 0:
        var d = carry

        if i >= 0:
            d += digit_value(a.get(i))
            i -= 1

        if j >= 0:
            d += digit_value(b.get(j))
            j -= 1

        out = "{d % 10}{out}"
        carry = d / 10

    return out

// Formats cents digits as "<int>.<2 digits>", removing leading zeros.
fn format_total(cents: String) String:
    var s = cents
    while s.length() > 1 and s.get(0) == "0":
        s = s.slice(1, s.length()).get()
    while s.length() < 3:
        s = "0{s}"

    let cut = s.length() - 2
    return "{s.slice(0, cut).get()}.{s.slice(cut, s.length()).get()}"

export fn main() Int:
    var totals = Map[String, String]()
    var skipped = 0
    let text = read_all(stdin()).get().decode_utf8().get()

    for line in text.lines():
        if line.trim_chars(" \t") == "":
            continue

        let rec = parse_line(line)

        if not rec.ok:
            skipped += 1
            continue

        let prev = totals.get(rec.category).get("0")
        totals[rec.category] = add_digits(prev, rec.amount)

    for key in totals.keys().sorted():
        stdout().write("{key}: {format_total(totals[key].clone())}\n").get()
    if skipped > 0:
        stdout().write("skipped: {skipped}\n").get()
    return 0
